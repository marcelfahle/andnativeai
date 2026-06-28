defmodule AndnativeAi.Slack.InstallationsTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.Installations

  test "upserts OAuth installs and resolves event payloads by team id" do
    tenant = tenant_fixture("slack-oauth")

    assert {:ok, installation} =
             Installations.upsert_oauth_installation(tenant.id, oauth_body("T123", "Acme"))

    assert installation.team_id == "T123"
    assert installation.team_name == "Acme"
    assert installation.bot_user_id == "UBOT"
    assert installation.bot_token == "xoxb-oauth"

    assert [listed] = Installations.list_installations(tenant.id)
    assert listed.id == installation.id

    payload = %{
      "team_id" => "T123",
      "event" => %{"type" => "app_mention", "team" => "T123"}
    }

    assert {:ok, tenant_id, opts} =
             Installations.resolve_payload(payload, tenant.id, client: FakeClient)

    assert tenant_id == tenant.id
    assert opts[:bot_token] == "xoxb-oauth"
    assert opts[:bot_user_id] == "UBOT"
  end

  test "reinstall updates the stored bot token for a workspace" do
    tenant = tenant_fixture("slack-reinstall")

    assert {:ok, first} =
             Installations.upsert_oauth_installation(tenant.id, oauth_body("T123", "Acme"))

    updated_body =
      "T123"
      |> oauth_body("Acme Renamed")
      |> Map.put("access_token", "xoxb-updated")

    assert {:ok, second} = Installations.upsert_oauth_installation(tenant.id, updated_body)

    assert second.id == first.id
    assert second.team_name == "Acme Renamed"
    assert second.bot_token == "xoxb-updated"
    assert [second] == Installations.list_installations(tenant.id)
  end

  test "env fallback still routes demo events when no OAuth install exists" do
    tenant = tenant_fixture("slack-env")

    payload = %{
      "team_id" => "TENV",
      "event" => %{"type" => "message", "team" => "TENV"}
    }

    assert {:ok, tenant_id, opts} =
             Installations.resolve_payload(payload, tenant.id,
               bot_token: "xoxb-env",
               bot_user_id: "UENV",
               team_id: "TENV"
             )

    assert tenant_id == tenant.id
    assert opts[:bot_token] == "xoxb-env"
    assert opts[:bot_user_id] == "UENV"
  end

  test "env fallback rejects events from a different configured team" do
    tenant = tenant_fixture("slack-env-reject")

    assert {:error, :unexpected_slack_team} =
             Installations.resolve_payload(
               %{"team_id" => "TOTHER", "event" => %{"team" => "TOTHER"}},
               tenant.id,
               bot_token: "xoxb-env",
               bot_user_id: "UENV",
               team_id: "TENV"
             )
  end

  defmodule FakeClient do
  end

  defp oauth_body(team_id, team_name) do
    %{
      "access_token" => "xoxb-oauth",
      "scope" => "app_mentions:read,channels:history,channels:read,chat:write",
      "bot_user_id" => "UBOT",
      "app_id" => "A123",
      "team" => %{"id" => team_id, "name" => team_name},
      "authed_user" => %{"id" => "UINSTALLER"},
      "enterprise" => nil
    }
  end

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: String.upcase(slug),
        slug: slug,
        status: "active"
      })

    tenant
  end
end
