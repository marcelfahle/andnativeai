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

  @doc """
  Which provider serves a model ID. Prefix-based: `claude-*` is
  Anthropic; everything else (gpt-*, o*, unknown, nil) defaults to
  OpenAI, matching the appliance default model.
  """
  def provider_for("claude-" <> _rest), do: :anthropic
  def provider_for(_model), do: :openai

  @doc """
  Resolves the client module and API key for a model, or the error the
  call site should degrade with. Missing/placeholder keys are reported
  per provider so the audit trail names the actual gap.
  """
  def model_client(model) do
    case provider_for(model) do
      :anthropic -> client_for(:anthropic, "ANTHROPIC_API_KEY", :anthropic_client)
      :openai -> client_for(:openai, "OPENAI_API_KEY", :openai_client)
    end
  end

  defp client_for(provider, key_env, client_env) do
    api_key = System.get_env(key_env, "")

    cond do
      api_key == "" ->
        {:error, :"missing_#{key_env |> String.downcase()}"}

      String.contains?(api_key, "replace-me") ->
        {:error, :"placeholder_#{key_env |> String.downcase()}"}

      true ->
        {:ok, Application.get_env(:andnative_ai, client_env, default_client(provider)), api_key}
    end
  end

  defp default_client(:anthropic), do: AndnativeAi.Runtime.AnthropicClient
  defp default_client(:openai), do: AndnativeAi.Runtime.OpenAIClient
end
