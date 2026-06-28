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

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the password with the correct current password", %{user: user} do
      {:ok, updated} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "a new valid password"
        })

      assert Accounts.get_user_by_email_and_password(user.email, "a new valid password")
      assert is_nil(updated.password)
    end

    test "rejects a wrong current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "wrong wrong wrong", %{password: "a new valid password"})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "validates the new password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: "short"})

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "invalidates the user's other sessions", %{user: user} do
      token = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "a new valid password"
        })

      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "reset password" do
    setup do
      %{user: user_fixture()}
    end

    test "deliver_user_reset_password_instructions emails a usable token", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert Accounts.get_user_by_reset_password_token(token).id == user.id
    end

    test "get_user_by_reset_password_token returns nil for an invalid token" do
      refute Accounts.get_user_by_reset_password_token("oops")
    end

    test "reset_user_password sets the password and clears reset + session tokens", %{user: user} do
      session = Accounts.generate_user_session_token(user)

      reset_token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, _} = Accounts.reset_user_password(user, %{password: "a brand new password"})

      assert Accounts.get_user_by_email_and_password(user.email, "a brand new password")
      refute Accounts.get_user_by_session_token(session)
      refute Accounts.get_user_by_reset_password_token(reset_token)
    end
  end

  describe "delete_user/1" do
    test "refuses to delete the last remaining user" do
      user = user_fixture()
      assert {:error, :last_user} = Accounts.delete_user(user)
      assert Accounts.get_user_by_email(user.email)
    end

    test "deletes a user when others remain" do
      keep = user_fixture()
      remove = user_fixture()

      assert {:ok, _} = Accounts.delete_user(remove)
      refute Accounts.get_user_by_email(remove.email)
      assert Accounts.get_user_by_email(keep.email)
    end
  end
end
