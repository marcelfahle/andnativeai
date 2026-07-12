defmodule AndnativeAi.Slack.SecretsEncryptionTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Repo
  alias AndnativeAi.Slack.{Installation, OAuthConfig}

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{name: String.upcase(slug), slug: slug, status: "active"})

    tenant
  end

  test "bot tokens are ciphertext at rest and plaintext through the schema" do
    tenant = tenant_fixture("secrets-install")

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        tenant_id: tenant.id,
        team_id: "T-SECRETS",
        team_name: "Secrets Test",
        bot_user_id: "UBOT",
        bot_token: "xoxb-super-secret-token",
        status: "active",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    # Schema round-trip decrypts transparently.
    assert Repo.get!(Installation, installation.id).bot_token == "xoxb-super-secret-token"

    # The raw column value is Cloak ciphertext, not the plaintext.
    %{rows: [[raw]]} =
      Repo.query!("SELECT bot_token FROM slack_installations WHERE id = $1", [installation.id])

    assert is_binary(raw)
    refute raw == "xoxb-super-secret-token"
    refute String.contains?(raw, "super-secret")
  end

  test "oauth client secrets are ciphertext at rest" do
    tenant = tenant_fixture("secrets-oauth")

    {:ok, config} =
      %OAuthConfig{}
      |> OAuthConfig.changeset(%{
        tenant_id: tenant.id,
        client_id: "12345.67890",
        client_secret: "shhh-oauth-client-secret",
        bot_scopes: "chat:write"
      })
      |> Repo.insert()

    assert Repo.get!(OAuthConfig, config.id).client_secret == "shhh-oauth-client-secret"

    %{rows: [[raw]]} =
      Repo.query!("SELECT client_secret FROM slack_oauth_configs WHERE id = $1", [config.id])

    refute raw == "shhh-oauth-client-secret"
    refute String.contains?(raw, "oauth-client")
  end

  test "inspect never leaks the secrets" do
    installation = %Installation{bot_token: "xoxb-hidden"}
    config = %OAuthConfig{client_secret: "hidden-secret"}

    refute inspect(installation) =~ "xoxb-hidden"
    refute inspect(config) =~ "hidden-secret"
  end
end
