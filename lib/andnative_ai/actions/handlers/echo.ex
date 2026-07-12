defmodule AndnativeAi.Actions.Handlers.Echo do
  @moduledoc """
  Demo handler: proves the mention → job → deliverable → audit loop without
  touching any external provider.
  """

  @behaviour AndnativeAi.Actions.Handler

  @impl true
  def run(action) do
    request = action.input["argument"] || action.input_summary

    markdown = """
    # Echo

    You asked for:

    > #{request}

    This document was produced by the governed action runner — requested in
    Slack, executed as a background job, delivered back to the thread, and
    recorded on the audit timeline under request `#{action.request_id}`.
    """

    {:ok,
     %{
       title: "Echo — #{String.slice(request, 0, 60)}",
       markdown: markdown,
       summary: "Echoed the request back as a markdown document.",
       provider: "internal"
     }}
  end
end
