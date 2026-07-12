defmodule AndnativeAi.Actions.DigestScheduler do
  @moduledoc """
  Cron entry point (Monday mornings) that requests a weekly digest action
  for every tenant with an active Slack channel. The digest posts as a
  top-level channel message via the normal action pipeline, so it is
  audited like everything else.
  """

  use Oban.Worker, queue: :actions, max_attempts: 2

  alias AndnativeAi.Actions
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Memory.list_tenants(), &schedule_for_tenant/1)
    :ok
  end

  defp schedule_for_tenant(tenant) do
    channel =
      tenant.id
      |> Memory.list_sources()
      |> Enum.filter(&(&1.source_type == "slack_channel" and not is_nil(&1.last_ingested_at)))
      |> Enum.max_by(& &1.last_ingested_at, DateTime, fn -> nil end)

    if channel do
      {:ok, _action} =
        Actions.request_action(tenant.id, %{
          kind: "weekly_digest",
          input_summary: "Weekly governed memory digest",
          request_id: Audit.new_request_id(),
          slack_channel_id: channel.source_id
        })
    end

    :ok
  end
end
