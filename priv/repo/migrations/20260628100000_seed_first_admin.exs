defmodule AndnativeAi.Repo.Migrations.SeedFirstAdmin do
  use Ecto.Migration

  # Bootstraps the first admin so a fresh deploy can log in immediately.
  #
  # Default password: changeme123 — the operator logs in and changes it at
  # /users/settings on first login. This is a deliberate, resettable bootstrap
  # value, not a real secret.
  #
  # Idempotent (ON CONFLICT DO NOTHING) and skipped for the test database so it
  # never pollutes the test suite's user table.
  def up do
    unless test_database?() do
      hashed_password = Bcrypt.hash_pwd_salt("changeme123")

      execute("""
      INSERT INTO users (email, hashed_password, inserted_at, updated_at)
      VALUES (
        'm.fahle@gmail.com',
        '#{hashed_password}',
        (NOW() AT TIME ZONE 'UTC'),
        (NOW() AT TIME ZONE 'UTC')
      )
      ON CONFLICT (email) DO NOTHING
      """)
    end
  end

  def down do
    execute("DELETE FROM users WHERE email = 'm.fahle@gmail.com'")
  end

  defp test_database? do
    %{rows: [[database]]} = repo().query!("SELECT current_database()")
    String.ends_with?(database, "_test")
  end
end
