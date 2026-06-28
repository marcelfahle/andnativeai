defmodule AndnativeAi.Slack.Installations do
  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Slack.Installation

  def list_installations(tenant_id) do
    Repo.all(
      from installation in Installation,
        where:
          installation.tenant_id == ^tenant_id and installation.status == "active" and
            is_nil(installation.deleted_at),
        order_by: [desc: installation.updated_at]
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

  def redirect_uri do
    System.get_env("SLACK_REDIRECT_URI", "")
  end

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
end
