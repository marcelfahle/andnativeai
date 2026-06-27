defmodule AndnativeAiWeb.PageController do
  use AndnativeAiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
