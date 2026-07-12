defmodule AndnativeAi.Runtime.ModelPolicy do
  @moduledoc """
  Resolves which model serves a capability for an agent.

  Customers pick an agent's *role*; which model runs underneath is a
  platform decision (superadmin-managed, see DEC-020). Resolution order:

    1. the agent's `model_policy` override for the capability
    2. the agent's base `model`
    3. the appliance default (`OPENAI_CHAT_MODEL`, falling back to
       `gpt-4.1-mini`)
  """

  alias AndnativeAi.Memory.Agent

  @capabilities ~w(chat write classify situate)

  def capabilities, do: @capabilities

  def resolve(agent, capability) when is_atom(capability),
    do: resolve(agent, Atom.to_string(capability))

  def resolve(%Agent{} = agent, capability) when capability in @capabilities do
    policy_override(agent, capability) || agent.model || default_model()
  end

  def resolve(nil, capability) when capability in @capabilities do
    default_model()
  end

  defp policy_override(%Agent{model_policy: policy}, capability) when is_map(policy) do
    case policy[capability] do
      value when is_binary(value) and value != "" -> value
      _unset -> nil
    end
  end

  defp policy_override(_agent, _capability), do: nil

  def default_model, do: System.get_env("OPENAI_CHAT_MODEL", "gpt-4.1-mini")
end
