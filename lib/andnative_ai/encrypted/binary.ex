defmodule AndnativeAi.Encrypted.Binary do
  @moduledoc "Ecto type for strings encrypted at rest via `AndnativeAi.Vault`."
  use Cloak.Ecto.Binary, vault: AndnativeAi.Vault
end
