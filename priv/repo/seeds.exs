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

# Seed ADDITIONAL admins from the environment.
#
# The first admin (m.fahle@gmail.com) is seeded by a migration with a default
# password (changed on first login), so it is not handled here. This block
# provisions any further users (e.g. Matt) from env-supplied passwords — no
# secret material ever lives in the repo.
#
# Re-running these seeds is idempotent: an existing user is left untouched (its
# password is NOT reset). To rotate or add a user, use the in-app reset/invite
# flows, or Accounts.register_user/1 from `iex -S mix`.
seed_admins = [
  %{email: System.get_env("SEED_MATT_EMAIL"), password_env: "SEED_MATT_PASSWORD"}
]

for %{email: email, password_env: password_env} <- seed_admins do
  cond do
    is_nil(email) ->
      IO.puts("• Skipping an admin: set SEED_MATT_EMAIL (and its password) to seed Matt.")

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
