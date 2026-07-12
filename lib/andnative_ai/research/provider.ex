defmodule AndnativeAi.Research.Provider do
  @moduledoc """
  Behaviour for deep-research providers. All supported providers are
  async-shaped: submit a query, poll until the report is ready — the lowest
  common denominator across Perplexity, Gemini, and Exa (webhook-capable
  providers can short-circuit polling later).

  A report is `%{markdown, citations, provider, cost_cents}` where
  `cost_cents` may be nil when the provider does not return spend.
  """

  @type job_ref :: term()
  @type report :: %{
          required(:markdown) => String.t(),
          required(:citations) => [String.t()],
          required(:provider) => String.t(),
          optional(:cost_cents) => non_neg_integer() | nil
        }

  @callback submit(query :: String.t(), opts :: keyword()) ::
              {:ok, job_ref()} | {:error, term()}
  @callback poll(job_ref()) :: {:pending, job_ref()} | {:done, report()} | {:error, term()}

  @doc "The configured provider module, or an error when none is usable."
  def configured do
    module = Application.get_env(:andnative_ai, :research_provider, default_provider())

    if module, do: {:ok, module}, else: {:error, :research_provider_not_configured}
  end

  defp default_provider do
    cond do
      System.get_env("PERPLEXITY_API_KEY", "") != "" -> AndnativeAi.Research.Perplexity
      System.get_env("GEMINI_API_KEY", "") != "" -> AndnativeAi.Research.Gemini
      true -> nil
    end
  end
end
