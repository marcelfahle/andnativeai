defmodule AndnativeAi.Accounts.UserToken do
  use Ecto.Schema

  import Ecto.Query

  alias AndnativeAi.Accounts.UserToken

  @rand_size 32

  # Session tokens are stored verbatim and expire after this many days, giving
  # logins a basic expiration window.
  @session_validity_in_days 60

  # Email tokens (reset, invite) are hashed at rest — only the SHA-256 hash is
  # stored, while the raw token travels in the emailed link. A DB read therefore
  # yields no usable token.
  @hash_algorithm :sha256
  @reset_password_validity_in_days 1
  @invite_validity_in_days 7

  schema "users_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :user, AndnativeAi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a random session token and the matching `UserToken` struct to persist.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Returns a query that fetches the user for a valid, unexpired session token.
  """
  def verify_session_token_query(token) do
    from token in by_token_and_context_query(token, "session"),
      join: user in assoc(token, :user),
      where: token.inserted_at > ago(@session_validity_in_days, "day"),
      select: user
  end

  @doc """
  Returns a query that fetches tokens by their raw value and context.
  """
  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Returns a query for all of a user's tokens, optionally filtered to specific
  contexts. Used to invalidate sessions and email tokens on password change.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc """
  Builds a hashed email token for the given context ("reset_password" or
  "invite"). Returns the raw, URL-safe token to email and the `UserToken`
  struct (carrying the hash) to persist.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{token: hashed_token, context: context, user_id: user.id}}
  end

  @doc """
  Returns `{:ok, query}` that fetches the user for a valid, unexpired email
  token, or `:error` when the token is not decodable.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context("invite"), do: @invite_validity_in_days

  defp days_for_context(context),
    do: raise(ArgumentError, "unknown email token context: #{inspect(context)}")
end
