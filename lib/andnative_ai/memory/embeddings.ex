defmodule AndnativeAi.Memory.Embeddings do
  @moduledoc """
  Embedding dispatch. The provider is chosen once per deployment
  (`:embeddings_provider` app env, else OpenAI when `OPENAI_API_KEY` is set,
  else the deterministic demo embedder) — queries and chunks must live in
  the same vector space, so never mix providers within one corpus without
  re-embedding (`AndnativeAi.Release.reembed_memory/0`).
  """

  @dimensions 1536

  def dimensions, do: @dimensions

  def embed(text) when is_binary(text), do: provider().embed(text)

  def provider do
    Application.get_env(:andnative_ai, :embeddings_provider) || default_provider()
  end

  @doc "Human label for the control plane, so demos are honest about mode."
  def provider_label do
    case provider() do
      AndnativeAi.Memory.Embeddings.OpenAI -> "OpenAI text-embedding-3-small"
      AndnativeAi.Memory.Embeddings.Deterministic -> "deterministic demo embeddings"
      module -> inspect(module)
    end
  end

  defp default_provider do
    api_key = System.get_env("OPENAI_API_KEY", "")

    if api_key != "" and not String.contains?(api_key, "replace-me") do
      AndnativeAi.Memory.Embeddings.OpenAI
    else
      AndnativeAi.Memory.Embeddings.Deterministic
    end
  end

  # Lexical terms for the rerank layer (provider-independent).

  @synonyms %{
    "approval" => ~w(approval approve approved authorization authorize),
    "authorize" => ~w(approval approve approved authorization authorize),
    "escalation" => ~w(escalation escalate handoff manager support),
    "handoff" => ~w(escalation escalate handoff manager support),
    "refund" => ~w(refund refunds reimbursement reimburse return),
    "reimbursement" => ~w(refund refunds reimbursement reimburse return),
    "source" => ~w(source citation permalink provenance reference),
    "citation" => ~w(source citation permalink provenance reference),
    "decision" => ~w(decision decide decided),
    "decided" => ~w(decision decide decided),
    "own" => ~w(owner own owns owned),
    "owner" => ~w(owner own owns owned)
  }

  def search_terms(text) when is_binary(text) do
    text |> expanded_tokens() |> MapSet.new()
  end

  @doc false
  def expanded_tokens(text) when is_binary(text) do
    text
    |> tokens()
    |> Enum.flat_map(&expand_token/1)
  end

  defp tokens(text) do
    Regex.scan(~r/[a-z0-9]+/u, String.downcase(text))
    |> List.flatten()
    |> Enum.map(&stem/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp stem(token) do
    cond do
      String.length(token) > 5 and String.ends_with?(token, "ing") ->
        String.trim_trailing(token, "ing")

      String.length(token) > 4 and String.ends_with?(token, "es") ->
        String.trim_trailing(token, "es")

      String.length(token) > 3 and String.ends_with?(token, "s") ->
        String.trim_trailing(token, "s")

      true ->
        token
    end
  end

  defp expand_token(token) do
    [token | Map.get(@synonyms, token, [])]
  end
end
