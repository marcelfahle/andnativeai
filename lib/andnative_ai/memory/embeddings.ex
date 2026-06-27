defmodule AndnativeAi.Memory.Embeddings do
  @dimensions 1536

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

  def dimensions, do: @dimensions

  def embed(text) when is_binary(text) do
    text
    |> tokens()
    |> Enum.flat_map(&expand_token/1)
    |> vectorize()
    |> Pgvector.new()
  end

  def search_terms(text) when is_binary(text) do
    text
    |> tokens()
    |> Enum.flat_map(&expand_token/1)
    |> MapSet.new()
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

  defp vectorize([]), do: List.duplicate(0.0, @dimensions)

  defp vectorize(tokens) do
    weights =
      Enum.reduce(tokens, %{}, fn token, acc ->
        index = :erlang.phash2(token, @dimensions)
        sign = if rem(:erlang.phash2("sign:" <> token), 2) == 0, do: 1.0, else: -1.0
        Map.update(acc, index, sign, &(&1 + sign))
      end)

    norm =
      weights
      |> Map.values()
      |> Enum.reduce(0.0, fn value, sum -> sum + value * value end)
      |> :math.sqrt()

    if norm == 0.0 do
      List.duplicate(0.0, @dimensions)
    else
      for index <- 0..(@dimensions - 1) do
        Map.get(weights, index, 0.0) / norm
      end
    end
  end
end
