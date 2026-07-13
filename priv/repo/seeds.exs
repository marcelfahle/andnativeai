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
# Platform slots run FIRST so a collision with the customer slot resolves
# in favor of the platform account's role (the provision script also
# rejects an admin email equal to a platform email).
seed_admins = [
  %{
    email: System.get_env("SEED_PLATFORM1_EMAIL"),
    password_env: "SEED_PLATFORM1_PASSWORD",
    role: "superadmin"
  },
  %{
    email: System.get_env("SEED_PLATFORM2_EMAIL"),
    password_env: "SEED_PLATFORM2_PASSWORD",
    role: "superadmin"
  },
  # Generic first admin for provisioned appliances (provision-appliance.sh).
  %{email: System.get_env("SEED_ADMIN_EMAIL"), password_env: "SEED_ADMIN_PASSWORD"},
  %{email: System.get_env("SEED_MATT_EMAIL"), password_env: "SEED_MATT_PASSWORD"}
]

for %{email: email, password_env: password_env} = slot <- seed_admins do
  role = Map.get(slot, :role, "admin")

  cond do
    is_nil(email) ->
      IO.puts("• Skipping an admin: no email set for this seed slot.")

    user = Accounts.get_user_by_email(email) ->
      # Existing users keep their password, but platform slots always
      # (re)assert the superadmin role — set_user_role/2 is idempotent.
      if role == "superadmin" and user.role != "superadmin" do
        {:ok, _user} = Accounts.set_user_role(user, "superadmin")
        IO.puts("✓ Promoted existing user #{email} to superadmin (password unchanged).")
      else
        IO.puts("• Admin #{email} already exists; leaving unchanged.")
      end

    password = System.get_env(password_env) ->
      case Accounts.register_user(%{email: email, password: password}) do
        {:ok, user} ->
          if role == "superadmin", do: {:ok, _} = Accounts.set_user_role(user, "superadmin")
          IO.puts("✓ Seeded #{role} #{email}.")

        {:error, changeset} ->
          IO.puts("✗ Could not seed admin #{email}: #{inspect(changeset.errors)}")
      end

    true ->
      IO.puts("• Skipping admin #{email}: set #{password_env} to seed this user.")
  end
end
