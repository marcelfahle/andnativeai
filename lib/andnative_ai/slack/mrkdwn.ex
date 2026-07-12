defmodule AndnativeAi.Slack.Mrkdwn do
  @moduledoc """
  Converts model-produced Markdown into Slack's mrkdwn so answers render
  instead of showing literal `**` and `[text](url)`. Applied at the Slack
  posting boundary only — stored documents keep real Markdown.
  """

  @doc "Best-effort Markdown → mrkdwn conversion, line-oriented."
  def from_markdown(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map_reduce(false, fn line, in_fence? ->
      fence_line? = line |> String.trim_leading() |> String.starts_with?("```")

      cond do
        fence_line? -> {line, not in_fence?}
        in_fence? -> {line, in_fence?}
        true -> {convert_line(line), in_fence?}
      end
    end)
    |> elem(0)
    |> Enum.join("\n")
  end

  def from_markdown(other), do: other

  defp convert_line(line) do
    line
    |> convert_heading()
    |> convert_links()
    |> convert_bold()
    |> convert_bullets()
  end

  # "## Heading" -> "*Heading*"
  defp convert_heading(line) do
    case Regex.run(~r/^(\#{1,6})\s+(.*)$/, line) do
      [_all, _hashes, title] -> "*#{strip_bold(title)}*"
      nil -> line
    end
  end

  # "[text](url)" -> "<url|text>"
  defp convert_links(line) do
    Regex.replace(~r/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, line, "<\\2|\\1>")
  end

  # "**bold**" / "__bold__" -> "*bold*"
  defp convert_bold(line) do
    line
    |> then(&Regex.replace(~r/\*\*([^*]+)\*\*/, &1, "*\\1*"))
    |> then(&Regex.replace(~r/__([^_]+)__/, &1, "*\\1*"))
  end

  # "- item" / "* item" -> "• item" (preserving indentation)
  defp convert_bullets(line) do
    Regex.replace(~r/^(\s*)[-*]\s+/, line, "\\1• ")
  end

  defp strip_bold(text), do: String.replace(text, "**", "")
end
