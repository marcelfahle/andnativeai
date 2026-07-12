defmodule AndnativeAi.Actions.Worker do
  @moduledoc """
  Runs one agent action: dispatch to the kind's handler, persist the
  deliverable under `RAW_SOURCES_PATH`, post it back to the Slack thread,
  and record the outcome as audit evidence.
  """

  use Oban.Worker, queue: :actions, max_attempts: 3

  alias AndnativeAi.Actions
  alias AndnativeAi.Actions.ActionKinds
  alias AndnativeAi.Slack.Client
  alias AndnativeAi.Slack.Installations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action_id" => action_id}}) do
    case AndnativeAi.Repo.get(AndnativeAi.Actions.Action, action_id) do
      nil ->
        # The action row is gone (tenant deleted, stale args): nothing to do.
        :ok

      %{status: status} = action when status in ["queued", "running"] ->
        execute(action)

      # Approvals or manual intervention changed the state; nothing to do.
      _other ->
        :ok
    end
  end

  # Any failure — error tuple or raise — cancels instead of retrying: a
  # retry would silently re-spend provider budget without a human deciding.
  defp execute(action) do
    action = Actions.mark_running(action)

    with {:ok, handler} <- fetch_handler(action.kind),
         {:ok, result} <- handler.run(action) do
      result_path = persist_result(action, result)
      deliver_to_slack(action, result)
      Actions.mark_completed(action, result, result_path)
      :ok
    else
      {:error, reason} -> fail(action, reason)
    end
  rescue
    exception -> fail(action, exception)
  end

  defp fail(action, reason) do
    Actions.mark_failed(action, reason)
    notify_failure(action)
    {:cancel, reason}
  end

  defp fetch_handler(kind) do
    case ActionKinds.fetch(kind) do
      {:ok, %{handler: handler}} -> {:ok, handler}
      :error -> {:error, {:unknown_action_kind, kind}}
    end
  end

  defp persist_result(action, result) do
    directory =
      Application.get_env(:andnative_ai, :raw_sources_path, "var/sources")
      |> Path.join("actions")
      |> Path.join(to_string(action.tenant_id))

    File.mkdir_p!(directory)
    path = Path.join(directory, "action-#{action.id}.md")
    File.write!(path, result.markdown)
    path
  end

  defp deliver_to_slack(%{slack_channel_id: nil}, _result), do: :ok

  defp deliver_to_slack(action, result) do
    case Installations.bot_credentials(action.tenant_id) do
      {:ok, bot_token, _bot_user_id} ->
        client = slack_client()

        # Sources stay on the governance audit trail; the Slack message is
        # for the person, not the auditor.
        message =
          AndnativeAi.Slack.Mrkdwn.from_markdown("*#{result.title}* is ready. #{result.summary}")

        client.post_message(bot_token, action.slack_channel_id, message, action.slack_thread_ts)

        if function_exported?(client, :upload_file, 5) do
          client.upload_file(
            bot_token,
            action.slack_channel_id,
            action.slack_thread_ts,
            "action-#{action.id}.md",
            result.markdown
          )
        end

        :ok

      :error ->
        :ok
    end
  end

  defp notify_failure(action) do
    with channel when is_binary(channel) <- action.slack_channel_id,
         {:ok, bot_token, _bot_user_id} <- Installations.bot_credentials(action.tenant_id) do
      slack_client().post_message(
        bot_token,
        channel,
        "That didn't work — the #{action.kind} action failed and the error is on the audit timeline.",
        action.slack_thread_ts
      )
    else
      _unavailable -> :ok
    end
  end

  defp slack_client do
    Application.get_env(:andnative_ai, :slack_client, Client)
  end
end
