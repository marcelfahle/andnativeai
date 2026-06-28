# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     AndnativeAi.Repo.insert!(%AndnativeAi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias AndnativeAi.{Accounts, Memory}

Memory.ensure_demo_tenant!()

# Seed the initial demo admins.
#
# Passwords are read from the environment so no secret material ever lives in
# the repo. Marcel (m.fahle@gmail.com) is always the first user. Matt's email
# can be overridden with SEED_MATT_EMAIL.
#
# Re-running these seeds is idempotent: an existing user is left untouched (its
# password is NOT reset). To rotate a password, delete the user first, then
# re-run with the new SEED_*_PASSWORD set, or use Accounts.register_user/1 from
# `iex -S mix`.
seed_admins = [
  %{email: "m.fahle@gmail.com", password_env: "SEED_MARCEL_PASSWORD"},
  %{
    email: System.get_env("SEED_MATT_EMAIL", "matt@example.com"),
    password_env: "SEED_MATT_PASSWORD"
  }
]

for %{email: email, password_env: password_env} <- seed_admins do
  cond do
    Accounts.get_user_by_email(email) ->
      IO.puts("• Admin #{email} already exists; leaving unchanged.")

    password = System.get_env(password_env) ->
      case Accounts.register_user(%{email: email, password: password}) do
        {:ok, _user} ->
          IO.puts("✓ Seeded admin #{email}.")

        {:error, changeset} ->
          IO.puts("✗ Could not seed admin #{email}: #{inspect(changeset.errors)}")
      end

    true ->
      IO.puts("• Skipping admin #{email}: set #{password_env} to seed this user.")
  end
end
