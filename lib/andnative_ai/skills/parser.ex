defmodule AndnativeAi.Skills.Parser do
  @moduledoc """
  Parses Agent Skills bundles (SKILL.md + optional references/) per the open
  spec at agentskills.io — restricted to phase-1 **prompt-pack skills**.

  Anything that could execute code is rejected outright: bundles with
  `scripts/`, frontmatter with the experimental `allowed-tools` grant, and
  the dynamic context-injection syntax (`` !`command` ``) anywhere in skill
  content. That single constraint removes the documented malicious-skill
  class (Snyk ToxicSkills, Datadog) while keeping prompt-only skills usable.
  """

  @injection_pattern ~r/!`[^`]*`/

  @doc """
  `files` is a map of relative path => content. Requires a `SKILL.md` at the
  bundle root. Returns `{:ok, %{name, description, body, references,
  license, compatibility}}` or `{:error, reason}`.
  """
  def parse(files) when is_map(files) do
    with {:ok, skill_md} <- fetch_skill_md(files),
         :ok <- reject_scripts(files),
         {:ok, frontmatter, body} <- split_frontmatter(skill_md),
         :ok <- reject_tool_grants(frontmatter),
         :ok <- reject_injection(files),
         {:ok, name} <- require_field(frontmatter, "name"),
         {:ok, description} <- require_field(frontmatter, "description") do
      {:ok,
       %{
         name: name,
         description: description,
         body: String.trim(body),
         references: reference_files(files),
         license: frontmatter["license"],
         compatibility: frontmatter["compatibility"]
       }}
    end
  end

  defp fetch_skill_md(files) do
    case Map.get(files, "SKILL.md") do
      content when is_binary(content) -> {:ok, content}
      nil -> {:error, :missing_skill_md}
    end
  end

  defp reject_scripts(files) do
    executable? = fn path ->
      segments = Path.split(path)
      "scripts" in segments or Path.extname(path) in ~w(.sh .py .js .rb .exs .ex .bash)
    end

    if Enum.any?(Map.keys(files), executable?) do
      {:error, :contains_scripts}
    else
      :ok
    end
  end

  defp reject_tool_grants(frontmatter) do
    if Map.has_key?(frontmatter, "allowed-tools") do
      {:error, :contains_tool_grants}
    else
      :ok
    end
  end

  defp reject_injection(files) do
    if Enum.any?(Map.values(files), &Regex.match?(@injection_pattern, &1)) do
      {:error, :contains_dynamic_injection}
    else
      :ok
    end
  end

  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n(.*)\z/s, content) do
      [_full, frontmatter, body] -> {:ok, parse_frontmatter(frontmatter), body}
      nil -> {:error, :missing_frontmatter}
    end
  end

  # Line-based `key: value` parsing covers the spec's frontmatter fields;
  # nested YAML (metadata maps) is intentionally ignored in phase 1.
  defp parse_frontmatter(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^([a-z-]+):\s*(.*)$/, line) do
        [_line, key, value] -> Map.put(acc, key, value |> String.trim() |> unquote_value())
        nil -> acc
      end
    end)
  end

  defp unquote_value(value) do
    value
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp require_field(frontmatter, key) do
    case Map.get(frontmatter, key, "") do
      "" -> {:error, {:missing_field, key}}
      value -> {:ok, value}
    end
  end

  defp reference_files(files) do
    files
    |> Enum.filter(fn {path, _content} ->
      String.starts_with?(path, "references/") and Path.extname(path) == ".md"
    end)
    |> Map.new()
  end
end
