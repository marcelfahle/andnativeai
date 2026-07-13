defmodule AndnativeAiWeb.Plugs.MemoryApiAuth do
  @moduledoc """
  Guards the memory search API with a shared token.

  The endpoint returns governed memory content for a tenant, so it must
  never be reachable without credentials. It fails **closed**: when
  `MEMORY_TOOL_TOKEN` is unset, every request is denied rather than
  silently left open. The token is compared in constant time.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) and token != "" <- System.get_env("MEMORY_TOOL_TOKEN"),
         ["Bearer " <> presented] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(presented, token) do
      conn
    else
      _denied ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
