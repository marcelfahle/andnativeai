defmodule AndnativeAi.Actions.Handlers.DeepResearch do
  @moduledoc """
  `research: <topic>` — submits the topic to the configured deep-research
  provider, polls until the cited report is ready (minutes), and returns it
  as a markdown dossier. Runs inside the action Oban job, so restarts and
  provider hiccups are survivable.
  """

  @behaviour AndnativeAi.Actions.Handler

  alias AndnativeAi.Research.Provider

  # Poll every 15s for up to 30 minutes by default.
  @default_poll_interval_ms 15_000
  @default_max_polls 120

  @impl true
  def run(action) do
    query = action.input["argument"] || action.input_summary

    with {:ok, provider} <- Provider.configured(),
         {:ok, job_ref} <- provider.submit(query, []),
         {:done, report} <- poll_until_done(provider, job_ref, 0) do
      {:ok,
       %{
         title: "Research dossier — #{String.slice(query, 0, 60)}",
         markdown: dossier_markdown(query, report),
         summary:
           "Deep research finished with #{length(report.citations)} cited sources" <>
             cost_note(report),
         provider: report.provider,
         cost_cents: report[:cost_cents],
         citations: report.citations
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll_until_done(provider, job_ref, attempt) do
    cond do
      attempt >= max_polls() ->
        {:error, :research_timed_out}

      attempt == 0 ->
        do_poll(provider, job_ref, attempt)

      true ->
        Process.sleep(poll_interval_ms())
        do_poll(provider, job_ref, attempt)
    end
  end

  defp do_poll(provider, job_ref, attempt) do
    case provider.poll(job_ref) do
      {:pending, job_ref} -> poll_until_done(provider, job_ref, attempt + 1)
      {:done, report} -> {:done, report}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dossier_markdown(query, report) do
    sources =
      case report.citations do
        [] ->
          ""

        citations ->
          listed =
            citations
            |> Enum.with_index(1)
            |> Enum.map_join("\n", fn {url, index} -> "#{index}. #{url}" end)

          "\n\n## Sources\n\n" <> listed
      end

    """
    # Research dossier

    **Question:** #{query}
    **Provider:** #{report.provider}

    ---

    #{report.markdown}
    """ <> sources
  end

  defp cost_note(%{cost_cents: cents}) when is_integer(cents),
    do: " (provider cost ~$#{Float.round(cents / 100, 2)})."

  defp cost_note(_report), do: "."

  defp poll_interval_ms,
    do: Application.get_env(:andnative_ai, :research_poll_interval_ms, @default_poll_interval_ms)

  defp max_polls, do: Application.get_env(:andnative_ai, :research_max_polls, @default_max_polls)
end
