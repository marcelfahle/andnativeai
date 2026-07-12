defmodule AndnativeAi.Actions.ActionKinds do
  @moduledoc """
  Registry of action kinds: Slack intent prefix, handler module, whether the
  action needs human approval before it runs (spend or outward-facing
  output), and display metadata.
  """

  @kinds %{
    "echo" => %{
      prefix: "echo:",
      handler: AndnativeAi.Actions.Handlers.Echo,
      requires_approval: false,
      label: "Echo (demo)",
      ack: "On it — echoing your request back as a document."
    },
    "deep_research" => %{
      prefix: "research:",
      handler: AndnativeAi.Actions.Handlers.DeepResearch,
      requires_approval: true,
      label: "Deep research",
      ack:
        "On it — deep research takes a few minutes. I'll post the cited dossier in this thread."
    }
  }

  def all, do: kinds()
  def keys, do: Map.keys(kinds())

  def fetch(kind), do: Map.fetch(kinds(), kind)

  def requires_approval?(kind) do
    case fetch(kind) do
      {:ok, meta} -> meta.requires_approval
      :error -> true
    end
  end

  @doc """
  Matches a mention text (bot mention already present) against the known
  intent prefixes. Returns `{:ok, kind, argument}` or `:error`.
  """
  def match_intent(text) when is_binary(text) do
    stripped =
      text
      |> String.replace(~r/<@[A-Z0-9]+>/, "")
      |> String.trim()

    Enum.find_value(kinds(), :error, fn {kind, meta} ->
      case strip_prefix(stripped, meta.prefix) do
        {:ok, argument} when argument != "" -> {:ok, kind, argument}
        _no_match -> nil
      end
    end)
  end

  def match_intent(_text), do: :error

  defp strip_prefix(text, prefix) do
    downcased = String.downcase(text)

    if String.starts_with?(downcased, prefix) do
      {:ok, text |> String.slice(String.length(prefix)..-1//1) |> String.trim()}
    else
      :error
    end
  end

  defp kinds do
    Map.merge(@kinds, Application.get_env(:andnative_ai, :extra_action_kinds, %{}))
  end
end
