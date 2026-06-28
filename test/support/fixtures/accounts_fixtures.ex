defmodule AndnativeAi.AccountsFixtures do
  @moduledoc """
  Test helpers for creating `AndnativeAi.Accounts` entities.
  """

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
end
