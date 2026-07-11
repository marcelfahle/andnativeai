defmodule AndnativeAiWeb.Admin.StatusPagesTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.Installations

  setup :register_and_log_in_user

  test "sources and Slack pages show Slack channel ingestion status", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _source} =
      Memory.upsert_source(tenant.id, %{
        source_type: "slack_channel",
        source_id: "CDEMO",
        name: "Slack CDEMO",
        permalink_or_url: "slack://channel/CDEMO",
        status: "ready"
      })

    {:ok, sources_view, _html} = live(conn, ~p"/admin/sources")
    assert has_element?(sources_view, "#slack-source-list [id^='source-']")

    {:ok, slack_view, _html} = live(conn, ~p"/admin/slack")
    assert has_element?(slack_view, "#slack-channels [id^='slack-source-']")
    assert has_element?(slack_view, "#slack-connection-status")
    assert has_element?(slack_view, "#slack-oauth-config-form")
  end

  test "sources page toggles app & bot post ingestion per channel", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, source} =
      Memory.upsert_source(tenant.id, %{
        source_type: "slack_channel",
        source_id: "CTOGGLE",
        name: "Slack CTOGGLE",
        permalink_or_url: "slack://channel/CTOGGLE",
        status: "ready"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/sources")

    refute AndnativeAi.Memory.Source.ingest_bot_messages?(
             Memory.get_source!(tenant.id, source.id)
           )

    view
    |> element("#toggle-bot-ingestion-#{source.id}")
    |> render_click()

    assert AndnativeAi.Memory.Source.ingest_bot_messages?(
             Memory.get_source!(tenant.id, source.id)
           )

    view
    |> element("#toggle-bot-ingestion-#{source.id}")
    |> render_click()

    refute AndnativeAi.Memory.Source.ingest_bot_messages?(
             Memory.get_source!(tenant.id, source.id)
           )
  end

  test "Slack page saves OAuth app settings", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, slack_view, _html} = live(conn, ~p"/admin/slack")

    slack_view
    |> form("#slack-oauth-config-form", %{
      oauth_config: %{
        client_id: "client-live",
        client_secret: "secret-live",
        redirect_uri: "https://live.example.com/slack/oauth/callback",
        bot_scopes: "app_mentions:read,chat:write"
      }
    })
    |> render_submit()

    assert Installations.oauth_configured?(tenant.id)

    settings = Installations.oauth_settings(tenant.id)
    assert settings.client_id == "client-live"
    assert settings.client_secret == "secret-live"
    assert settings.redirect_uri == "https://live.example.com/slack/oauth/callback"

    assert render(slack_view) =~ "Saved; leave blank to keep"
  end

  test "runtime page shows OpenClaw health without raw gateway controls", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _agent} =
      Memory.create_agent(tenant.id, %{
        name: "Runtime Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/runtime")

    assert has_element?(view, "#runtime-agents [id^='runtime-agent-']")
    refute render(view) =~ "gateway admin"
  end
end
