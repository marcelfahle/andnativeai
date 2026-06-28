defmodule AndnativeAi.Accounts.UserNotifierTest do
  use AndnativeAi.DataCase, async: true

  import Swoosh.TestAssertions
  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts.UserNotifier

  test "deliver_reset_password_instructions sends an email containing the link" do
    user = user_fixture()

    {:ok, email} =
      UserNotifier.deliver_reset_password_instructions(user, "https://example.com/reset/abc")

    assert_email_sent(email)
    assert email.to == [{"", user.email}]
    assert email.subject =~ "Reset"
    assert email.text_body =~ "https://example.com/reset/abc"
  end

  test "deliver_invitation sends an email containing the link" do
    user = user_fixture()

    {:ok, email} =
      UserNotifier.deliver_invitation(user, "https://example.com/invite/xyz")

    assert_email_sent(email)
    assert email.to == [{"", user.email}]
    assert email.subject =~ "invited"
    assert email.text_body =~ "https://example.com/invite/xyz"
  end
end
