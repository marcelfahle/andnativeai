defmodule AndnativeAiWeb.SlackOAuthControllerTest do
  use AndnativeAiWeb.ConnCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.Installations

  setup do
    env_keys = ~w(SLACK_CLIENT_ID SLACK_CLIENT_SECRET SLACK_REDIRECT_URI SLACK_BOT_SCOPES)
    previous_env = Map.new(env_keys, &{&1, System.get_env(&1)})
    previous_client = Application.get_env(:andnative_ai, :slack_client)

    System.put_env("SLACK_CLIENT_ID", "123.abc")
    System.put_env("SLACK_CLIENT_SECRET", "secret")
    System.put_env("SLACK_REDIRECT_URI", "https://app.example.com/slack/oauth/callback")
    System.put_env("SLACK_BOT_SCOPES", "app_mentions:read,channels:history,chat:write")
    Application.put_env(:andnative_ai, :slack_client, __MODULE__.FakeOAuthClient)

    on_exit(fn ->
      Enum.each(previous_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      if previous_client do
        Application.put_env(:andnative_ai, :slack_client, previous_client)
      else
        Application.delete_env(:andnative_ai, :slack_client)
      end
    end)

    :ok
  end

  setup :register_and_log_in_user

  test "install redirects to Slack OAuth with state and configured scopes", %{conn: conn} do
    conn =
      conn
      |> get(~p"/slack/install")

    assert redirected_to(conn) =~ "https://slack.com/oauth/v2/authorize?"

    state = get_session(conn, :slack_oauth_state)
    assert is_binary(state)

    uri = URI.parse(redirected_to(conn))
    query = URI.decode_query(uri.query)

    assert query["client_id"] == "123.abc"
    assert query["scope"] == "app_mentions:read,channels:history,chat:write"
    assert query["redirect_uri"] == "https://app.example.com/slack/oauth/callback"
    assert query["state"] == state
  end

  test "callback exchanges the code and stores the Slack install", %{conn: conn} do
    conn =
      conn
      |> get(~p"/slack/install")

    state = get_session(conn, :slack_oauth_state)

    conn =
      get(conn, ~p"/slack/oauth/callback", %{
        "code" => "valid-code",
        "state" => state
      })

    assert redirected_to(conn) == ~p"/admin/slack"

    tenant = Memory.ensure_demo_tenant!()
    installation = Installations.latest_installation(tenant.id)

    assert installation.team_id == "T123"
    assert installation.team_name == "Acme"
    assert installation.bot_token == "xoxb-oauth"
    assert installation.bot_user_id == "UBOT"
  end

  test "callback rejects mismatched state", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{slack_oauth_state: "expected"})
      |> get(~p"/slack/oauth/callback", %{
        "code" => "valid-code",
        "state" => "wrong"
      })

    assert redirected_to(conn) == ~p"/admin/slack"

    tenant = Memory.ensure_demo_tenant!()
    assert Installations.latest_installation(tenant.id) == nil
  end

  test "install can use OAuth app settings saved in the database", %{conn: conn} do
    System.delete_env("SLACK_CLIENT_ID")
    System.delete_env("SLACK_CLIENT_SECRET")
    System.delete_env("SLACK_REDIRECT_URI")

    tenant = Memory.ensure_demo_tenant!()

    {:ok, _config} =
      Installations.upsert_oauth_config(tenant.id, %{
        "client_id" => "db.client",
        "client_secret" => "db-secret",
        "redirect_uri" => "https://db.example.com/slack/oauth/callback",
        "bot_scopes" => "channels:read,chat:write"
      })

    conn =
      conn
      |> get(~p"/slack/install")

    assert redirected_to(conn) =~ "https://slack.com/oauth/v2/authorize?"

    query =
      conn
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query["client_id"] == "db.client"
    assert query["redirect_uri"] == "https://db.example.com/slack/oauth/callback"
    assert query["scope"] == "channels:read,chat:write"
  end

  test "install reports missing OAuth config", %{conn: conn} do
    System.delete_env("SLACK_CLIENT_SECRET")

    conn =
      conn
      |> get(~p"/slack/install")

    assert redirected_to(conn) == ~p"/admin/slack"
  end

  test "install requires authentication" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> get(~p"/slack/install")

    assert redirected_to(conn) == ~p"/login"
  end

  test "OAuth callback stays reachable without authentication" do
    # Slack calls the callback directly, so it must remain public — an
    # unauthenticated request runs the controller rather than redirecting to login.
    conn =
      build_conn()
      |> init_test_session(%{slack_oauth_state: "expected"})
      |> get(~p"/slack/oauth/callback", %{"code" => "valid-code", "state" => "wrong"})

    assert redirected_to(conn) == ~p"/admin/slack"
  end

  defmodule FakeOAuthClient do
    def oauth_v2_access(
          "123.abc",
          "secret",
          "valid-code",
          "https://app.example.com/slack/oauth/callback"
        ) do
      {:ok,
       %{
         "access_token" => "xoxb-oauth",
         "scope" => "app_mentions:read,channels:history,chat:write",
         "bot_user_id" => "UBOT",
         "app_id" => "A123",
         "team" => %{"id" => "T123", "name" => "Acme"},
         "authed_user" => %{"id" => "UINSTALLER"}
       }}
    end

    def oauth_v2_access(
          "db.client",
          "db-secret",
          "valid-code",
          "https://db.example.com/slack/oauth/callback"
        ) do
      {:ok,
       %{
         "access_token" => "xoxb-db",
         "scope" => "channels:read,chat:write",
         "bot_user_id" => "UDBBOT",
         "app_id" => "ADB",
         "team" => %{"id" => "TDB", "name" => "Database Config"},
         "authed_user" => %{"id" => "UINSTALLER"}
       }}
    end
  end
end
