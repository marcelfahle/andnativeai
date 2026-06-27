defmodule AndnativeAiWeb.PageController do
  use AndnativeAiWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/admin/agents")
  end
end
