defmodule AndnativeAi.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  # Two-level model per the provisioning plan: "admin" is a customer
  # appliance admin; "superadmin" is platform staff (fleet operations,
  # model policy). Customers can never grant superadmin from the UI.
  @roles ~w(admin superadmin)

  @derive {Inspect, except: [:password]}
  schema "users" do
    # Stored as citext in Postgres, so email comparison/uniqueness is
    # case-insensitive at the database level.
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :role, :string, default: "admin"

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def superadmin?(%__MODULE__{role: "superadmin"}), do: true
  def superadmin?(_user), do: false

  @doc """
  A changeset for changing a user's role. Deliberately separate from every
  other changeset so role can only change through an explicit, audited path.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> check_constraint(:role, name: :users_role_must_be_known)
  end

  @doc """
  A changeset for registering users with an email and password.

  Options:

    * `:hash_password` - hash the password so it can be stored. Defaults to `true`.
    * `:validate_email` - validate uniqueness of the email against the database.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, AndnativeAi.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A changeset for changing the password (used by settings, reset, and invite
  acceptance). Validates and hashes the new password; does not touch the email.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_password(opts)
  end

  @doc """
  Validates the current password — adds an error to `:current_password` when it
  does not match the user's stored password.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks that could be used to learn
  whether an email is registered.
  """
  def valid_password?(%AndnativeAi.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
