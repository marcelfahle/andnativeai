defmodule AndnativeAi.Slack.Installations do
  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Slack.{Installation, OAuthConfig}

  def list_installations(tenant_id) do
    Repo.all(
      from installation in Installation,
        where:
          installation.tenant_id == ^tenant_id and installation.status == "active" and
            is_nil(installation.deleted_at),
        order_by: [desc: installation.updated_at]
    )
  end

  def count_installations(tenant_id) do
    Repo.one(
      from installation in Installation,
        where:
          installation.tenant_id == ^tenant_id and installation.status == "active" and
            is_nil(installation.deleted_at),
        select: count(installation.id)
    )
  end

  def latest_installation(tenant_id) do
    Repo.one(
      from installation in Installation,
        where:
          installation.tenant_id == ^tenant_id and installation.status == "active" and
            is_nil(installation.deleted_at),
        order_by: [desc: installation.updated_at],
        limit: 1
    )
  end

  @doc """
  Resolves bot credentials for outbound Slack calls: the latest OAuth
  installation first, `SLACK_BOT_TOKEN`/`SLACK_BOT_USER_ID` env fallback
  second. Returns `{:ok, bot_token, bot_user_id}` or `:error`.
  """
  def bot_credentials(tenant_id) do
    case latest_installation(tenant_id) do
      %{bot_token: token, bot_user_id: user_id}
      when is_binary(token) and token != "" and is_binary(user_id) and user_id != "" ->
        {:ok, token, user_id}

      _no_installation ->
        with token when token != "" <- System.get_env("SLACK_BOT_TOKEN", ""),
             user_id when user_id != "" <- System.get_env("SLACK_BOT_USER_ID", "") do
          {:ok, token, user_id}
        else
          _missing -> :error
        end
    end
  end

  def get_active_by_team_id(nil), do: nil

  def get_active_by_team_id(team_id) do
    Repo.one(
      from installation in Installation,
        where:
          installation.team_id == ^team_id and installation.status == "active" and
            is_nil(installation.deleted_at),
        limit: 1
    )
  end

  def get_oauth_config(tenant_id), do: Repo.get_by(OAuthConfig, tenant_id: tenant_id)

  def upsert_oauth_config(tenant_id, attrs) do
    existing = get_oauth_config(tenant_id)

    attrs =
      attrs
      |> normalize_oauth_attrs()
      |> Map.put(:tenant_id, tenant_id)
      |> Map.update(:bot_scopes, default_scopes(), &default_if_blank(&1, default_scopes()))
      |> maybe_preserve_client_secret(existing)

    (existing || %OAuthConfig{})
    |> OAuthConfig.changeset(attrs)
    |> upsert_config(existing)
  end

  def upsert_oauth_installation(tenant_id, oauth_body) do
    attrs = attrs_from_oauth(tenant_id, oauth_body)

    case get_active_by_team_id(attrs.team_id) do
      nil ->
        %Installation{}
        |> Installation.changeset(attrs)
        |> Repo.insert()

      %Installation{} = installation ->
        installation
        |> Installation.changeset(attrs)
        |> Repo.update()
    end
  end

  def resolve_payload(payload, fallback_tenant_id, base_opts) do
    team_id = team_id_from_payload(payload)

    case get_active_by_team_id(team_id) do
      %Installation{} = installation ->
        {:ok, installation.tenant_id, merge_installation_opts(base_opts, installation)}

      nil ->
        resolve_env_fallback(team_id, fallback_tenant_id, base_opts)
    end
  end

  def team_id_from_payload(payload) when is_map(payload) do
    event = Map.get(payload, "event", %{})

    payload["team_id"] ||
      get_in(payload, ["team", "id"]) ||
      event["team_id"] ||
      event["team"] ||
      first_authorization_team_id(payload)
  end

  def team_id_from_payload(_payload), do: nil

  def env_fallback_configured? do
    valid_secret?(System.get_env("SLACK_BOT_TOKEN", "")) and
      System.get_env("SLACK_BOT_USER_ID", "") != ""
  end

  def configured_app_token? do
    valid_secret?(System.get_env("SLACK_APP_TOKEN", ""))
  end

  def oauth_settings(tenant_id) do
    case get_oauth_config(tenant_id) do
      %OAuthConfig{} = config ->
        %{
          source: :database,
          client_id: config.client_id || "",
          client_secret: config.client_secret || "",
          client_secret_set?: configured?(config.client_secret || ""),
          redirect_uri: default_if_blank(config.redirect_uri, env_redirect_uri()),
          bot_scopes: default_if_blank(config.bot_scopes, default_scopes())
        }

      nil ->
        %{
          source: :env,
          client_id: System.get_env("SLACK_CLIENT_ID", ""),
          client_secret: System.get_env("SLACK_CLIENT_SECRET", ""),
          client_secret_set?: configured?(System.get_env("SLACK_CLIENT_SECRET", "")),
          redirect_uri: env_redirect_uri(),
          bot_scopes: default_scopes()
        }
    end
  end

  def oauth_configured?(tenant_id) do
    settings = oauth_settings(tenant_id)
    configured?(settings.client_id) and configured?(settings.client_secret)
  end

  def oauth_configured? do
    configured?(System.get_env("SLACK_CLIENT_ID", "")) and
      configured?(System.get_env("SLACK_CLIENT_SECRET", ""))
  end

  def default_scopes do
    System.get_env(
      "SLACK_BOT_SCOPES",
      "app_mentions:read,channels:history,channels:read,chat:write"
    )
  end

  def redirect_uri(tenant_id) do
    tenant_id
    |> oauth_settings()
    |> Map.fetch!(:redirect_uri)
  end

  def redirect_uri do
    env_redirect_uri()
  end

  def client_id(tenant_id), do: tenant_id |> oauth_settings() |> Map.fetch!(:client_id)
  def client_secret(tenant_id), do: tenant_id |> oauth_settings() |> Map.fetch!(:client_secret)
  def bot_scopes(tenant_id), do: tenant_id |> oauth_settings() |> Map.fetch!(:bot_scopes)

  defp attrs_from_oauth(tenant_id, body) do
    team = Map.get(body, "team") || %{}
    enterprise = Map.get(body, "enterprise") || %{}
    authed_user = Map.get(body, "authed_user") || %{}

    %{
      tenant_id: tenant_id,
      team_id: team["id"] || body["team_id"],
      team_name: team["name"] || body["team_name"] || "Slack workspace",
      enterprise_id: enterprise["id"] || body["enterprise_id"],
      app_id: body["app_id"],
      bot_user_id: body["bot_user_id"],
      bot_token: body["access_token"],
      bot_scopes: body["scope"],
      installed_by_user_id: authed_user["id"],
      status: "active",
      installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      deleted_at: nil
    }
  end

  defp upsert_config(changeset, nil), do: Repo.insert(changeset)
  defp upsert_config(changeset, %OAuthConfig{}), do: Repo.update(changeset)

  defp normalize_oauth_attrs(attrs) do
    attrs
    |> Enum.reduce(%{}, fn
      {key, value}, acc when key in ["client_id", :client_id] ->
        Map.put(acc, :client_id, normalize_string(value))

      {key, value}, acc when key in ["client_secret", :client_secret] ->
        Map.put(acc, :client_secret, normalize_string(value))

      {key, value}, acc when key in ["redirect_uri", :redirect_uri] ->
        Map.put(acc, :redirect_uri, normalize_string(value))

      {key, value}, acc when key in ["bot_scopes", :bot_scopes] ->
        Map.put(acc, :bot_scopes, normalize_string(value))

      _other, acc ->
        acc
    end)
  end

  defp maybe_preserve_client_secret(attrs, %OAuthConfig{} = existing) do
    if blank?(Map.get(attrs, :client_secret)) do
      Map.put(attrs, :client_secret, existing.client_secret)
    else
      attrs
    end
  end

  defp maybe_preserve_client_secret(attrs, nil), do: attrs

  defp default_if_blank(value, default) do
    if blank?(value), do: default, else: value
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(nil), do: ""
  defp normalize_string(value), do: value

  defp blank?(value), do: value in [nil, ""]

  defp merge_installation_opts(base_opts, %Installation{} = installation) do
    base_opts
    |> Keyword.put(:bot_token, installation.bot_token)
    |> Keyword.put(:bot_user_id, installation.bot_user_id)
  end

  defp resolve_env_fallback(team_id, fallback_tenant_id, base_opts) do
    expected_team_id = Keyword.get(base_opts, :team_id, System.get_env("SLACK_TEAM_ID", ""))
    bot_token = Keyword.get(base_opts, :bot_token, System.get_env("SLACK_BOT_TOKEN", ""))
    bot_user_id = Keyword.get(base_opts, :bot_user_id, System.get_env("SLACK_BOT_USER_ID", ""))

    cond do
      not valid_secret?(bot_token) or bot_user_id == "" ->
        {:error, :no_matching_slack_installation}

      expected_team_id not in ["", team_id] ->
        {:error, :unexpected_slack_team}

      true ->
        opts =
          base_opts
          |> Keyword.put(:bot_token, bot_token)
          |> Keyword.put(:bot_user_id, bot_user_id)

        {:ok, fallback_tenant_id, opts}
    end
  end

  defp first_authorization_team_id(%{"authorizations" => [authorization | _]})
       when is_map(authorization) do
    authorization["team_id"]
  end

  defp first_authorization_team_id(_payload), do: nil

  defp configured?(value), do: value != "" and not String.contains?(value, "replace-me")

  defp valid_secret?(value), do: configured?(value)

  defp env_redirect_uri, do: System.get_env("SLACK_REDIRECT_URI", "")
end
