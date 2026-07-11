defmodule AndnativeAi.Runtime.Audit do
  @moduledoc """
  Persists runtime and source-lifecycle audit evidence for the control plane.
  """

  import Ecto.Query

  require Logger

  alias AndnativeAi.Repo
  alias AndnativeAi.Runtime.AuditEvent
  alias AndnativeAi.Runtime.AuditEventKinds

  @pubsub AndnativeAi.PubSub

  @blocked_metadata_key_fragments ~w(
    answer
    authorization
    body
    bot_token
    payload
    question
    raw
    response
    secret
    text
    token
  )
  @attr_keys %{
    "tenant_id" => :tenant_id,
    "agent_id" => :agent_id,
    "source_id" => :source_id,
    "memory_item_id" => :memory_item_id,
    "request_id" => :request_id,
    "event_kind" => :event_kind,
    "component" => :component,
    "actor" => :actor,
    "status" => :status,
    "summary" => :summary,
    "metadata" => :metadata,
    "citation_url" => :citation_url,
    "occurred_at" => :occurred_at
  }
  @max_metadata_string 300

  def new_request_id, do: Ecto.UUID.generate()

  def request_id_from_event(%{"_andnative_request_id" => request_id}) when is_binary(request_id),
    do: request_id

  def request_id_from_event(%{"request_id" => request_id}) when is_binary(request_id),
    do: request_id

  def request_id_from_event(%{"event_id" => event_id})
      when is_binary(event_id) and event_id != "",
      do: "slack:#{event_id}"

  def request_id_from_event(%{"channel" => channel, "ts" => ts})
      when is_binary(channel) and channel != "" and is_binary(ts) and ts != "" do
    "slack:#{channel}:#{ts}"
  end

  def request_id_from_event(_event), do: new_request_id()

  def reason_summary(reason) when is_binary(reason), do: sanitize_string(reason)
  def reason_summary(reason) when is_atom(reason), do: Atom.to_string(reason)

  def reason_summary(reason),
    do:
      reason
      |> sanitize_metadata_value()
      |> inspect(limit: 20, printable_limit: @max_metadata_string)
      |> sanitize_string()

  def record_event(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, tenant_id} <- fetch_tenant_id(attrs) do
      attrs =
        attrs
        |> Map.delete(:tenant_id)
        |> Map.update(:metadata, %{}, &sanitize_metadata/1)

      %AuditEvent{tenant_id: tenant_id}
      |> AuditEvent.changeset(attrs)
      |> Repo.insert()
      |> broadcast_recorded()
    end
  end

  @doc """
  Subscribes the calling process to live audit events for a tenant. Each
  recorded event arrives as `{:audit_event_recorded, %AuditEvent{}}`.
  """
  def subscribe(tenant_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(tenant_id))
  end

  defp topic(tenant_id), do: "audit_events:#{tenant_id}"

  defp broadcast_recorded({:ok, event} = result) do
    Phoenix.PubSub.broadcast(@pubsub, topic(event.tenant_id), {:audit_event_recorded, event})
    result
  end

  defp broadcast_recorded(result), do: result

  def record_best_effort(attrs) do
    case record_event(attrs) do
      {:ok, event} ->
        {:ok, event}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("Audit event rejected: #{inspect(changeset.errors)}")
        {:error, changeset}

      {:error, reason} ->
        Logger.warning("Audit event failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.warning("Audit event failed: #{Exception.message(error)}")
      {:error, error}
  end

  def list_recent_events(tenant_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 20) |> clamp_limit()
    preload = Keyword.get(opts, :preload, [])

    Repo.all(
      from event in AuditEvent,
        where: event.tenant_id == ^tenant_id,
        order_by: [desc: event.occurred_at, desc: event.id],
        limit: ^limit,
        preload: ^preload
    )
  end

  @doc """
  Lists audit events for the control-plane timeline with optional filters.

  Options:

    * `:category` - a category key from `AuditEventKinds.categories/0`
      (atom or string); restricts to that category's event kinds
    * `:query` - matches request id, summary, actor, or event kind (ilike)
    * `:before_id` - cursor for pagination; returns events with a smaller id
    * `:limit` - page size, clamped to 1..100 (default 25)
    * `:preload` - associations to preload
  """
  def list_events(tenant_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 25) |> clamp_limit()
    preload = Keyword.get(opts, :preload, [])

    AuditEvent
    |> where([event], event.tenant_id == ^tenant_id)
    |> apply_category(Keyword.get(opts, :category))
    |> apply_query(Keyword.get(opts, :query))
    |> apply_cursor(Keyword.get(opts, :before_id))
    |> order_by([event], desc: event.occurred_at, desc: event.id)
    |> limit(^limit)
    |> preload(^preload)
    |> Repo.all()
  end

  @doc "Counts events per category for the current tenant."
  def category_counts(tenant_id) do
    kind_counts =
      AuditEvent
      |> where([event], event.tenant_id == ^tenant_id)
      |> group_by([event], event.event_kind)
      |> select([event], {event.event_kind, count(event.id)})
      |> Repo.all()

    Enum.reduce(kind_counts, %{all: 0}, fn {kind, count}, acc ->
      category = AuditEventKinds.category(kind)

      acc
      |> Map.update(:all, count, &(&1 + count))
      |> Map.update(category, count, &(&1 + count))
    end)
  end

  @doc "Counts events of one kind for the tenant."
  def count_events_by_kind(tenant_id, kind) do
    AuditEvent
    |> where([event], event.tenant_id == ^tenant_id and event.event_kind == ^kind)
    |> select([event], count(event.id))
    |> Repo.one()
  end

  @doc "Fetches one tenant-scoped event, or nil."
  def get_event(tenant_id, id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    AuditEvent
    |> where([event], event.tenant_id == ^tenant_id and event.id == ^id)
    |> preload(^preload)
    |> Repo.one()
  end

  @doc """
  Returns the full correlated trace for one request id, oldest first, so a
  single governed action reads as a story: mention -> search -> answer ->
  citation -> delivery.
  """
  def list_request_events(tenant_id, request_id, opts \\ [])

  def list_request_events(_tenant_id, request_id, _opts)
      when request_id in [nil, ""],
      do: []

  def list_request_events(tenant_id, request_id, opts) do
    preload = Keyword.get(opts, :preload, [])

    Repo.all(
      from event in AuditEvent,
        where: event.tenant_id == ^tenant_id and event.request_id == ^request_id,
        order_by: [asc: event.occurred_at, asc: event.id],
        preload: ^preload
    )
  end

  defp apply_category(queryable, nil), do: queryable
  defp apply_category(queryable, "all"), do: queryable
  defp apply_category(queryable, :all), do: queryable

  defp apply_category(queryable, category) do
    case AuditEventKinds.kinds_for_category(category) do
      [] -> queryable
      kinds -> where(queryable, [event], event.event_kind in ^kinds)
    end
  end

  defp apply_query(queryable, query) when is_binary(query) and query != "" do
    pattern = "%#{sanitize_like(query)}%"

    where(
      queryable,
      [event],
      ilike(event.request_id, ^pattern) or
        ilike(event.summary, ^pattern) or
        ilike(event.actor, ^pattern) or
        ilike(event.event_kind, ^pattern)
    )
  end

  defp apply_query(queryable, _query), do: queryable

  defp apply_cursor(queryable, before_id) when is_integer(before_id) do
    where(queryable, [event], event.id < ^before_id)
  end

  defp apply_cursor(queryable, _before_id), do: queryable

  defp sanitize_like(query) do
    String.replace(query, ~r/[%_\\]/, fn char -> "\\" <> char end)
  end

  def sanitize_metadata(metadata) when is_map(metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, acc ->
      key = to_string(key)

      if blocked_metadata_key?(key) do
        acc
      else
        Map.put(acc, key, sanitize_metadata_value(value))
      end
    end)
  end

  def sanitize_metadata(_metadata), do: %{}

  defp sanitize_metadata_value(value) when is_binary(value) do
    value
    |> sanitize_string()
    |> truncate_string()
  end

  defp sanitize_metadata_value(value) when is_map(value), do: sanitize_metadata(value)

  defp sanitize_metadata_value(value) when is_list(value) do
    Enum.map(value, &sanitize_metadata_value/1)
  end

  defp sanitize_metadata_value(value) when is_boolean(value), do: value
  defp sanitize_metadata_value(value) when is_atom(value), do: to_string(value)
  defp sanitize_metadata_value(value), do: value

  defp sanitize_string(value) do
    value
    |> redact(~r/xox[baprs]-[A-Za-z0-9-]+/)
    |> redact(~r/sk-[A-Za-z0-9_-]+/)
    |> redact(~r/(token|secret|authorization|password)=([^&\s]+)/i)
    |> redact(~r/(token|secret|authorization|password):\s*([^\s,}]+)/i)
  end

  defp redact(value, pattern), do: Regex.replace(pattern, value, "[REDACTED]")

  defp truncate_string(value) do
    if String.length(value) > @max_metadata_string do
      String.slice(value, 0, @max_metadata_string) <> "..."
    else
      value
    end
  end

  defp blocked_metadata_key?(key) do
    normalized = String.downcase(key)
    Enum.any?(@blocked_metadata_key_fragments, &String.contains?(normalized, &1))
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@attr_keys, key) do
          {:ok, atom_key} -> Map.put(acc, atom_key, value)
          :error -> acc
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp fetch_tenant_id(%{tenant_id: tenant_id}) when not is_nil(tenant_id), do: {:ok, tenant_id}
  defp fetch_tenant_id(_attrs), do: {:error, :missing_tenant_id}

  defp clamp_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(100)
  defp clamp_limit(_limit), do: 20
end
