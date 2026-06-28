defmodule AndnativeAi.Accounts do
  @moduledoc """
  The Accounts context.

  Provides app-level email/password authentication for the admin UI: user
  registration (used by seeds and operational provisioning), credential
  verification, and database-backed session tokens.
  """

  import Ecto.Query, warn: false

  alias AndnativeAi.Repo
  alias AndnativeAi.Accounts.{User, UserToken}

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

  @doc """
  Gets a single user. Raises `Ecto.NoResultsError` if the user does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user from the given attributes (`:email`, `:password`).
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking user registration changes (e.g. in a form).
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
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
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the given session token. Used on logout.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
