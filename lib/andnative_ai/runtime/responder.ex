defmodule AndnativeAi.Runtime.Responder do
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Slack.Client

  def respond_to_slack(tenant_id, slack_event, opts \\ []) do
    if mention_or_owned_thread?(slack_event, opts) do
      agent = Keyword.get(opts, :agent) || default_agent!(tenant_id)
      adapter = Keyword.get(opts, :adapter, OpenClaw)

      with {:ok, response} <- adapter.dispatch_mention(agent, slack_event) do
        maybe_post_response(slack_event, response.answer, opts)
        {:ok, response}
      end
    else
      {:ignored, :not_mentioned}
    end
  end

  defp mention_or_owned_thread?(%{"type" => "app_mention"}, _opts), do: true

  defp mention_or_owned_thread?(%{"thread_ts" => thread_ts}, opts) do
    thread_ts in Keyword.get(opts, :owned_threads, [])
  end

  defp mention_or_owned_thread?(_event, _opts), do: false

  defp default_agent!(tenant_id) do
    case Memory.list_agents(tenant_id) do
      [agent | _] -> agent
      [] -> raise "No agent configured for tenant #{tenant_id}"
    end
  end

  defp maybe_post_response(%{"channel" => channel} = event, answer, opts) do
    client = Keyword.get(opts, :client, Client)
    bot_token = Keyword.get(opts, :bot_token, "")

    if bot_token != "" and function_exported?(client, :post_message, 4) do
      thread_ts = event["thread_ts"] || event["ts"]
      client.post_message(bot_token, channel, answer, thread_ts)
    end
  end
end
