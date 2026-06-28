defmodule AndnativeAi.MailerResendTest do
  @moduledoc """
  Verifies the production Resend path: delivering a UserNotifier email through
  `Swoosh.Adapters.Resend` issues the expected Resend API request. Uses a fake
  Swoosh API client so no network call is made.
  """
  use AndnativeAi.DataCase, async: false

  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts.UserNotifier

  defmodule CapturingClient do
    @behaviour Swoosh.ApiClient

    @impl true
    def init, do: :ok

    @impl true
    def post(url, headers, body, _email) do
      send(self(), {:resend_request, url, headers, IO.iodata_to_binary(body)})
      {:ok, 200, [], ~s({"id":"00000000-0000-0000-0000-000000000000"})}
    end
  end

  setup do
    previous_mailer = Application.get_env(:andnative_ai, AndnativeAi.Mailer)
    previous_client = Application.get_env(:swoosh, :api_client)

    Application.put_env(:swoosh, :api_client, CapturingClient)

    Application.put_env(:andnative_ai, AndnativeAi.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: "re_test_123"
    )

    on_exit(fn ->
      Application.put_env(:andnative_ai, AndnativeAi.Mailer, previous_mailer)

      if previous_client do
        Application.put_env(:swoosh, :api_client, previous_client)
      else
        Application.delete_env(:swoosh, :api_client)
      end
    end)

    :ok
  end

  test "delivers a reset email via Resend with bearer auth and the email in the body" do
    user = user_fixture()

    {:ok, _email} =
      UserNotifier.deliver_reset_password_instructions(user, "https://example.com/reset/tok-abc")

    assert_received {:resend_request, url, headers, body}

    assert IO.iodata_to_binary(url) =~ "https://api.resend.com/emails"
    assert {"Authorization", "Bearer re_test_123"} in headers
    assert body =~ user.email
    assert body =~ "Reset your"
    assert body =~ "https://example.com/reset/tok-abc"
  end
end
