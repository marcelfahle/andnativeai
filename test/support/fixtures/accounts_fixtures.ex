defmodule AndnativeAi.AccountsFixtures do
  @moduledoc """
  Test helpers for creating `AndnativeAi.Accounts` entities.
  """

  import ExUnit.Assertions

  alias AndnativeAi.Accounts

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "hello world!12345"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  @doc """
  Runs `fun` with a URL builder that wraps the token in markers, then extracts
  the emailed token from the email captured by the Swoosh test adapter. Works
  regardless of `fun`'s return value.
  """
  def extract_user_token(fun) do
    fun.(&"[TOKEN]#{&1}[TOKEN]")
    assert_received {:email, email}
    [_, token | _] = String.split(email.text_body, "[TOKEN]")
    token
  end
end
