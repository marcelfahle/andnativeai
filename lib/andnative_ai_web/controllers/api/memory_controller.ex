defmodule AndnativeAiWeb.Api.MemoryController do
  use AndnativeAiWeb, :controller

  alias AndnativeAi.Runtime.MemoryTool

  def search(conn, params) do
    case MemoryTool.call(params) do
      {:ok, results} -> json(conn, %{results: results})
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end
end
