defmodule AndnativeAi.Accounts.UserTokenTest do
  use AndnativeAi.DataCase, async: true

  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts.UserToken

  describe "build_email_token/2" do
    test "stores a SHA-256 hash and returns the raw URL-safe token" do
      user = user_fixture()
      {encoded, token_struct} = UserToken.build_email_token(user, "reset_password")

      assert is_binary(encoded)
      {:ok, raw} = Base.url_decode64(encoded, padding: false)
      assert token_struct.token == :crypto.hash(:sha256, raw)
      refute token_struct.token == raw
      assert token_struct.context == "reset_password"
      assert token_struct.user_id == user.id
    end
  end

  describe "verify_email_token_query/2" do
    setup do
      user = user_fixture()
      {encoded, token_struct} = UserToken.build_email_token(user, "reset_password")
      inserted = Repo.insert!(token_struct)
      %{user: user, encoded: encoded, token_struct: inserted}
    end

    test "returns the user for a valid token", %{user: user, encoded: encoded} do
      {:ok, query} = UserToken.verify_email_token_query(encoded, "reset_password")
      assert Repo.one(query).id == user.id
    end

    test "rejects a token used under the wrong context", %{encoded: encoded} do
      {:ok, query} = UserToken.verify_email_token_query(encoded, "invite")
      refute Repo.one(query)
    end

    test "returns :error for a malformed token" do
      assert :error = UserToken.verify_email_token_query("not valid base64!!", "reset_password")
    end

    test "rejects an expired token", %{encoded: encoded, token_struct: token_struct} do
      {1, _} =
        Repo.update_all(
          from(t in UserToken, where: t.id == ^token_struct.id),
          set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
        )

      {:ok, query} = UserToken.verify_email_token_query(encoded, "reset_password")
      refute Repo.one(query)
    end
  end
end
