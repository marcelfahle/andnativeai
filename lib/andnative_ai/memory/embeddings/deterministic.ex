defmodule AndnativeAi.Memory.Embeddings.Deterministic do
  @moduledoc """
  Hash-based demo embeddings: repeatable without credentials, guarded at
  search time by the lexical rerank (DEC-006). Kept as the test/dev
  default and the fallback when no provider key exists.
  """

  alias AndnativeAi.Memory.Embeddings

  def embed(text) when is_binary(text) do
    text
    |> Embeddings.expanded_tokens()
    |> vectorize()
    |> Pgvector.new()
  end

  defp vectorize([]), do: List.duplicate(0.0, Embeddings.dimensions())

  defp vectorize(tokens) do
    dimensions = Embeddings.dimensions()

    weights =
      Enum.reduce(tokens, %{}, fn token, acc ->
        index = :erlang.phash2(token, dimensions)
        sign = if rem(:erlang.phash2("sign:" <> token), 2) == 0, do: 1.0, else: -1.0
        Map.update(acc, index, sign, &(&1 + sign))
      end)

    norm =
      weights
      |> Map.values()
      |> Enum.reduce(0.0, fn value, sum -> sum + value * value end)
      |> :math.sqrt()

    if norm == 0.0 do
      List.duplicate(0.0, dimensions)
    else
      for index <- 0..(dimensions - 1) do
        Map.get(weights, index, 0.0) / norm
      end
    end
  end
end
