defmodule AndnativeAi.Actions do
  @moduledoc """
  Governed agent actions: long-running work requested in Slack, executed as
  Oban jobs, delivered back to the thread, and recorded as audit evidence.
  Actions whose kind requires approval pause in `awaiting_approval` until a
  human decides on the control plane.
  """

  import Ecto.Query

  alias AndnativeAi.Actions.{Action, ActionKinds, Worker}
  alias AndnativeAi.Repo
  alias AndnativeAi.Runtime.Audit

  @doc """
  Creates an action from a matched Slack intent and either enqueues it or
  parks it for approval. Returns `{:ok, action}`.
  """
  def request_action(tenant_id, attrs) do
    kind = Map.fetch!(attrs, :kind)
    requires_approval? = ActionKinds.requires_approval?(kind)
    status = if requires_approval?, do: "awaiting_approval", else: "queued"

    result =
      %Action{tenant_id: tenant_id}
      |> Action.changeset(Map.merge(attrs, %{status: status}))
      |> Repo.insert()

    with {:ok, action} <- result do
      record_action_event(action, "action_requested", %{
        status: status,
        summary: action_summary(action, requested_summary(action, requires_approval?))
      })

      unless requires_approval?, do: enqueue(action)

      {:ok, action}
    end
  end

  @doc "Approves a parked action and enqueues it. Audited."
  def approve_action(tenant_id, action_id, approver) do
    action = get_action!(tenant_id, action_id)

    {:ok, action} =
      action
      |> Action.changeset(%{
        status: "queued",
        approved_by: approver,
        approved_at: utc_now()
      })
      |> Repo.update()

    record_action_event(action, "action_approved", %{
      actor: approver,
      status: "approved",
      summary: action_summary(action, "was approved by #{approver}.")
    })

    enqueue(action)
    {:ok, action}
  end

  @doc "Denies a parked action. Audited; nothing runs."
  def deny_action(tenant_id, action_id, approver) do
    action = get_action!(tenant_id, action_id)

    {:ok, action} =
      action
      |> Action.changeset(%{status: "denied", approved_by: approver, approved_at: utc_now()})
      |> Repo.update()

    record_action_event(action, "action_denied", %{
      actor: approver,
      status: "denied",
      summary: action_summary(action, "was denied by #{approver}.")
    })

    {:ok, action}
  end

  def get_action!(tenant_id, id), do: Repo.get_by!(Action, id: id, tenant_id: tenant_id)

  def list_pending_approvals(tenant_id) do
    Repo.all(
      from action in Action,
        where: action.tenant_id == ^tenant_id and action.status == "awaiting_approval",
        order_by: [asc: action.inserted_at]
    )
  end

  def count_pending_approvals(tenant_id) do
    Repo.one(
      from action in Action,
        where: action.tenant_id == ^tenant_id and action.status == "awaiting_approval",
        select: count(action.id)
    )
  end

  def list_recent_actions(tenant_id, limit \\ 10) do
    Repo.all(
      from action in Action,
        where: action.tenant_id == ^tenant_id,
        order_by: [desc: action.inserted_at],
        limit: ^limit
    )
  end

  @doc "Transitions and audits from within the worker."
  def mark_running(%Action{} = action) do
    {:ok, action} = action |> Action.changeset(%{status: "running"}) |> Repo.update()

    record_action_event(action, "action_started", %{
      status: "running",
      summary: action_summary(action, "started running.")
    })

    action
  end

  def mark_completed(%Action{} = action, result, result_path) do
    {:ok, action} =
      action
      |> Action.changeset(%{
        status: "completed",
        result_path: result_path,
        result_preview: String.slice(result.summary, 0, 500),
        provider: Map.get(result, :provider),
        cost_cents: Map.get(result, :cost_cents),
        completed_at: utc_now()
      })
      |> Repo.update()

    record_action_event(action, "action_completed", %{
      status: "completed",
      summary: action_summary(action, "completed and delivered."),
      metadata: %{
        provider: Map.get(result, :provider),
        cost_cents: Map.get(result, :cost_cents),
        citation_count: result |> Map.get(:citations, []) |> length()
      }
    })

    action
  end

  def mark_failed(%Action{} = action, reason) do
    sanitized = Audit.reason_summary(reason)

    {:ok, action} =
      action
      |> Action.changeset(%{status: "failed", error: String.slice(sanitized, 0, 255)})
      |> Repo.update()

    record_action_event(action, "action_failed", %{
      status: "error",
      summary: action_summary(action, "failed."),
      metadata: %{reason: sanitized}
    })

    action
  end

  defp enqueue(%Action{} = action) do
    %{action_id: action.id}
    |> Worker.new()
    |> Oban.insert!()
  end

  defp requested_summary(_action, true), do: "was requested and awaits human approval."
  defp requested_summary(_action, false), do: "was requested."

  defp action_summary(action, rest) do
    label =
      case ActionKinds.fetch(action.kind) do
        {:ok, meta} -> meta.label
        :error -> action.kind
      end

    "#{label} action \"#{action.input_summary}\" #{rest}"
  end

  defp record_action_event(action, event_kind, overrides) do
    attrs =
      Map.merge(
        %{
          tenant_id: action.tenant_id,
          agent_id: action.agent_id,
          request_id: action.request_id,
          event_kind: event_kind,
          component: "action_runner",
          actor: "Action runner",
          status: action.status,
          summary: "",
          metadata: %{action_id: action.id, kind: action.kind}
        },
        Map.new(overrides, fn
          {:metadata, extra} ->
            {:metadata, Map.merge(%{action_id: action.id, kind: action.kind}, extra)}

          pair ->
            pair
        end)
      )

    case Application.get_env(:andnative_ai, :audit_recorder, Audit) do
      recorder when is_function(recorder, 1) -> recorder.(attrs)
      recorder -> recorder.record_best_effort(attrs)
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
