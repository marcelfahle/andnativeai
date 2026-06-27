defmodule AndnativeAi.Runtime.Adapter do
  alias AndnativeAi.Memory.Agent

  @callback sync_agent(Agent.t()) :: {:ok, Agent.t()} | {:error, term()}
  @callback dispatch_mention(Agent.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback health(Agent.t() | map()) :: map()
end
