defmodule AndnativeAi.Accounts.UserToken do
  use Ecto.Schema

  import Ecto.Query

  alias AndnativeAi.Accounts.UserToken

  @rand_size 32

  # Session tokens are stored verbatim and expire after this many days, giving
  # logins a basic expiration window.
  @session_validity_in_days 60

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
end
