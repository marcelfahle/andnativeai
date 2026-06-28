defmodule AndnativeAiWeb.SlackOAuthController do
  use AndnativeAiWeb, :controller

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.{Client, Installations}

  @authorize_url "https://slack.com/oauth/v2/authorize"

  def install(conn, _params) do
    tenant = Memory.ensure_demo_tenant!()

    if Installations.oauth_configured?() do
      state = oauth_state()

      conn
      |> put_session(:slack_oauth_state, state)
      |> put_session(:slack_oauth_tenant_id, tenant.id)
      |> redirect(external: authorize_url(state))
    else
      conn
      |> put_flash(:error, "Slack OAuth is missing SLACK_CLIENT_ID or SLACK_CLIENT_SECRET.")
      |> redirect(to: ~p"/admin/slack")
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> clear_oauth_session()
    |> put_flash(:error, "Slack install was cancelled or rejected: #{error}.")
    |> redirect(to: ~p"/admin/slack")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    tenant_id = get_session(conn, :slack_oauth_tenant_id) || Memory.ensure_demo_tenant!().id

    with :ok <- verify_state(conn, state),
         {:ok, body} <-
           client().oauth_v2_access(client_id(), client_secret(), code, redirect_uri()),
         {:ok, installation} <- Installations.upsert_oauth_installation(tenant_id, body) do
      conn
      |> clear_oauth_session()
      |> put_flash(:info, "Connected Slack workspace #{installation.team_name}.")
      |> redirect(to: ~p"/admin/slack")
    else
      {:error, reason} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, oauth_error(reason))
        |> redirect(to: ~p"/admin/slack")
    end
  end

  def callback(conn, _params) do
    conn
    |> clear_oauth_session()
    |> put_flash(:error, "Slack install callback was missing a code.")
    |> redirect(to: ~p"/admin/slack")
  end

  defp authorize_url(state) do
    query =
      %{
        client_id: client_id(),
        scope: Installations.default_scopes(),
        redirect_uri: redirect_uri(),
        state: state
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> URI.encode_query()

    @authorize_url <> "?" <> query
  end

  defp verify_state(conn, state) do
    expected = get_session(conn, :slack_oauth_state)

    if is_binary(expected) and is_binary(state) and Plug.Crypto.secure_compare(expected, state) do
      :ok
    else
      {:error, :invalid_oauth_state}
    end
  end

  defp clear_oauth_session(conn) do
    conn
    |> delete_session(:slack_oauth_state)
    |> delete_session(:slack_oauth_tenant_id)
  end

  defp oauth_state do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp oauth_error(:invalid_oauth_state), do: "Slack install state did not match. Try again."

  defp oauth_error(%{"error" => error}), do: "Slack install failed: #{error}."

  defp oauth_error(_reason), do: "Slack install failed."

  defp redirect_uri do
    case Installations.redirect_uri() do
      "" -> url(~p"/slack/oauth/callback")
      uri -> uri
    end
  end

  defp client_id, do: System.get_env("SLACK_CLIENT_ID", "")
  defp client_secret, do: System.get_env("SLACK_CLIENT_SECRET", "")

  defp client do
    Application.get_env(:andnative_ai, :slack_client, Client)
  end
end
