defmodule AndnativeAi.Sources.CollectionClassifier do
  @moduledoc """
  Proposes a collection (name, kind, description) for a batch of uploaded
  documents. The proposal is always confirmed or edited by a human before it
  takes effect — this module only suggests.

  Uses the configured OpenAI key for a classification call when available;
  otherwise falls back to a deterministic filename heuristic so the flow
  works in development and demos without credentials.
  """

  alias AndnativeAi.Memory.Collection
  alias AndnativeAi.Runtime.OpenAIClient

  @kind_hints [
    {"handbook", ~w(handbook onboarding getting-started benefits perks career rituals)},
    {"policies", ~w(policy policies compliance security legal severance fmla moonlighting)},
    {"meeting_notes", ~w(meeting notes standup retro transcript minutes)},
    {"product", ~w(product spec roadmap feature release architecture api)},
    {"research", ~w(research dossier report analysis study)}
  ]

  @doc """
  `files` is a list of `%{filename: String.t(), preview: String.t()}` (the
  preview being the first ~500 chars). `suggested_name` typically comes from
  the uploaded folder or zip name. Returns
  `%{name: _, kind: _, description: _}` — never errors.
  """
  def propose(files, suggested_name \\ nil) do
    llm_propose(files, suggested_name) || heuristic_propose(files, suggested_name)
  end

  defp llm_propose(files, suggested_name) do
    with api_key when is_binary(api_key) and api_key != "" <-
           System.get_env("OPENAI_API_KEY", ""),
         {:ok, proposal} <- request_llm_proposal(files, suggested_name, api_key) do
      proposal
    else
      _unavailable -> nil
    end
  end

  defp request_llm_proposal(files, suggested_name, api_key) do
    listing =
      files
      |> Enum.take(20)
      |> Enum.map_join("\n", fn file ->
        "- #{file.filename}: #{String.slice(file.preview || "", 0, 200)}"
      end)

    input = """
    Suggested name (from folder/zip, may be empty): #{suggested_name || "-"}.
    Files:
    #{listing}
    """

    request = %{
      model: System.get_env("OPENAI_MODEL", "gpt-4.1-mini"),
      api_key: api_key,
      instructions: """
      You classify a batch of company documents into one collection.
      Kinds: #{Enum.join(Collection.kinds() -- ["conversation"], ", ")}.
      Reply with strict JSON only:
      {"name": "...", "kind": "...", "description": "one or two sentences describing what this corpus is and what questions it answers"}
      """,
      input: input,
      max_output_tokens: 220
    }

    case OpenAIClient.response(request) do
      {:ok, content} -> parse_llm_json(content)
      _error -> :error
    end
  end

  defp parse_llm_json(content) do
    with {:ok, json} <- extract_json(content),
         {:ok, decoded} <- Jason.decode(json),
         name when is_binary(name) <- decoded["name"],
         description when is_binary(description) <- decoded["description"] do
      kind =
        if decoded["kind"] in Collection.kinds(), do: decoded["kind"], else: "custom"

      {:ok, %{name: name, kind: kind, description: description}}
    else
      _invalid -> :error
    end
  end

  defp extract_json(content) do
    case Regex.run(~r/\{.*\}/s, content) do
      [json] -> {:ok, json}
      _none -> :error
    end
  end

  defp heuristic_propose(files, suggested_name) do
    filenames = Enum.map(files, &String.downcase(&1.filename))
    kind = guess_kind(filenames)
    name = suggested_name || default_name(kind)

    shown = files |> Enum.take(5) |> Enum.map_join(", ", & &1.filename)
    more = if length(files) > 5, do: " and #{length(files) - 5} more", else: ""

    %{
      name: name,
      kind: kind,
      description:
        "#{length(files)} documents including #{shown}#{more}. Confirm or edit this description so answers can cite the right context."
    }
  end

  defp guess_kind(filenames) do
    joined = Enum.join(filenames, " ")

    @kind_hints
    |> Enum.map(fn {kind, keywords} ->
      {kind, Enum.count(keywords, &String.contains?(joined, &1))}
    end)
    |> Enum.max_by(fn {_kind, hits} -> hits end)
    |> case do
      {kind, hits} when hits > 0 -> kind
      _no_signal -> "custom"
    end
  end

  defp default_name("handbook"), do: "Company handbook"
  defp default_name("policies"), do: "Policies"
  defp default_name("meeting_notes"), do: "Meeting notes"
  defp default_name("product"), do: "Product docs"
  defp default_name("research"), do: "Research"
  defp default_name(_kind), do: "New collection"
end
