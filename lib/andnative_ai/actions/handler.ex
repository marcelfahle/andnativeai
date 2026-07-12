defmodule AndnativeAi.Actions.Handler do
  @moduledoc """
  Behaviour for action handlers. A handler receives the persisted action and
  produces a markdown deliverable. Long-running work (provider polling)
  happens inside `run/1` — the surrounding Oban job provides retries and
  restart safety.
  """

  alias AndnativeAi.Actions.Action

  @type result :: %{
          required(:title) => String.t(),
          required(:markdown) => String.t(),
          required(:summary) => String.t(),
          optional(:provider) => String.t(),
          optional(:cost_cents) => non_neg_integer(),
          optional(:citations) => [String.t()]
        }

  @callback run(Action.t()) :: {:ok, result()} | {:error, term()}
end
