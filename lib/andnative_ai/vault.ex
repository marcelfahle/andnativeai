defmodule AndnativeAi.Vault do
  @moduledoc """
  Cloak vault for secrets encrypted at rest (Slack bot tokens, OAuth client
  secrets). The AES-256-GCM key comes from `CLOAK_KEY` in production
  (base64, 32 bytes — generate with
  `openssl rand -base64 32`); dev/test use a fixed key from config.
  """

  use Cloak.Vault, otp_app: :andnative_ai
end

defmodule AndnativeAi.Encrypted.Binary do
  @moduledoc "Ecto type for strings encrypted at rest via `AndnativeAi.Vault`."
  use Cloak.Ecto.Binary, vault: AndnativeAi.Vault
end
