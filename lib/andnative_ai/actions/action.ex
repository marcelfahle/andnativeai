defmodule AndnativeAi.Actions.Action do
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(queued awaiting_approval running completed failed denied)

  schema "agent_actions" do
    field :kind, :string
    field :status, :string, default: "queued"
    field :input_summary, :string
    field :input, :map, default: %{}
    field :result_path, :string
    field :result_preview, :string
    field :error, :string
    field :provider, :string
    field :cost_cents, :integer
    field :request_id, :string
    field :slack_channel_id, :string
    field :slack_thread_ts, :string
    field :approved_by, :string
    field :approved_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :tenant, AndnativeAi.Memory.Tenant
    belongs_to :agent, AndnativeAi.Memory.Agent

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :kind,
      :status,
      :input_summary,
      :input,
      :result_path,
      :result_preview,
      :error,
      :provider,
      :cost_cents,
      :request_id,
      :slack_channel_id,
      :slack_thread_ts,
      :agent_id,
      :approved_by,
      :approved_at,
      :completed_at
    ])
    |> validate_required([:tenant_id, :kind, :status, :input_summary])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:input_summary, max: 255)
  end
end
