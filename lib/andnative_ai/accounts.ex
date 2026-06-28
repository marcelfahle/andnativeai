defmodule AndnativeAi.Accounts do
  @moduledoc """
  The Accounts context.

  Provides app-level email/password authentication for the admin UI: user
  registration (used by seeds and operational provisioning), credential
  verification, and database-backed session tokens.
  """

  import Ecto.Query, warn: false

  alias AndnativeAi.Repo
  alias AndnativeAi.Accounts.{User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email. Returns `nil` if no user exists with that email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  Returns the user when the credentials are valid, otherwise `nil`. Always runs
  a password check (even when the email is unknown) so the response time does
  not reveal whether an account exists.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  ## User registration

  @doc """
  Registers a user from the given attributes (`:email`, `:password`).
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Session

  @doc """
  Generates a session token, persists it, and returns the raw token value to
  store in the signed session cookie.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user for the given signed session token, or `nil` when the token is
  missing, unknown, or expired.
  """
  def get_user_by_session_token(token) do
    Repo.one(UserToken.verify_session_token_query(token))
  end

  @doc """
  Deletes the given session token. Used on logout.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Passwords

  @doc """
  Changes a user's password after verifying the current one, and invalidates the
  user's other sessions in the same transaction.
  """
  def update_user_password(user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(current_password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["session"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking password changes in a form.
  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  ## Reset password

  @doc """
  Delivers reset-password instructions for the given user. The caller must not
  reveal whether an email exists (no enumeration).
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user for a valid reset-password token, or `nil`.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user's password and invalidates the user's reset and session tokens.
  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["reset_password", "session"])
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Invitations

  @doc """
  Invites a new user by email: creates the user with a random (unguessable)
  password and an unset `confirmed_at`, then emails an activation link. The
  invitee sets their real password via `accept_invitation/2`.
  """
  def invite_user(email, invite_url_fun) when is_function(invite_url_fun, 1) do
    random_password = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    case register_user(%{email: email, password: random_password}) do
      {:ok, user} ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "invite")
        Repo.insert!(user_token)
        {:ok, _email} = UserNotifier.deliver_invitation(user, invite_url_fun.(encoded_token))
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets the user for a valid invite token, or `nil`.
  """
  def get_user_by_invite_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invite"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Accepts an invitation: sets the invitee's chosen password, stamps
  `confirmed_at`, and clears the user's invite and session tokens.
  """
  def accept_invitation(user, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    changeset =
      user
      |> User.password_changeset(attrs)
      |> Ecto.Changeset.put_change(:confirmed_at, now)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["invite", "session"])
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## User administration

  @doc """
  Deletes a user, refusing to remove the final remaining user so the system can
  never be locked out.
  """
  def delete_user(%User{} = user) do
    if Repo.aggregate(User, :count) <= 1 do
      {:error, :last_user}
    else
      Repo.delete(user)
    end
  end
end
