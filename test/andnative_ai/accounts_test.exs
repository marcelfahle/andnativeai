defmodule AndnativeAi.AccountsTest do
  use AndnativeAi.DataCase, async: true

  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               email: ["can't be blank"],
               password: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates password minimum length" do
      {:error, changeset} =
        Accounts.register_user(%{email: unique_user_email(), password: "short"})

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "creates a user with a hashed password and does not persist the plaintext" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      refute user.hashed_password == valid_user_password()
    end

    test "rejects duplicate emails case-insensitively (citext)" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(valid_user_attributes(email: String.upcase(email)))

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user with valid credentials" do
      user = user_fixture()
      assert found = Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert found.id == user.id
    end

    test "returns nil for a wrong password" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong wrong wrong")
    end

    test "returns nil and does not raise for an unknown email" do
      refute Accounts.get_user_by_email_and_password("nobody@example.com", valid_user_password())
    end

    test "matches the email case-insensitively (citext)" do
      email = unique_user_email()
      user_fixture(email: email)

      assert found =
               Accounts.get_user_by_email_and_password(
                 String.upcase(email),
                 valid_user_password()
               )

      assert found.email == email
    end
  end

  describe "session tokens" do
    test "generate then lookup round-trips to the same user" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "delete invalidates the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end

    test "does not return a user for an expired token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      {1, _} =
        Repo.update_all(
          from(t in AndnativeAi.Accounts.UserToken, where: t.token == ^token),
          set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
        )

      refute Accounts.get_user_by_session_token(token)
    end
  end
end
