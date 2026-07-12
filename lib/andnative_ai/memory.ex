defmodule AndnativeAi.Memory do
  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Memory.{Agent, Collection, Item, Source, Tenant}
  alias AndnativeAi.Runtime.Audit

  ## Collections

  @doc """
  Creates a collection and records the governance decision as audit
  evidence. `opts[:actor]` names who confirmed the collection.
  """
  def create_collection(tenant_id, attrs, opts \\ []) do
    result =
      %Collection{tenant_id: tenant_id}
      |> Collection.changeset(attrs)
      |> Repo.insert()

    with {:ok, collection} <- result do
      record_audit_best_effort(%{
        tenant_id: tenant_id,
        event_kind: "collection_created",
        component: "control_panel",
        actor: Keyword.get(opts, :actor, "Admin"),
        status: "confirmed",
        summary: "Collection \"#{collection.name}\" (#{collection.kind}) was confirmed.",
        metadata: %{collection_id: collection.id, kind: collection.kind},
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      {:ok, collection}
    end
  end

  def list_collections(tenant_id) do
    Repo.all(
      from collection in Collection,
        where: collection.tenant_id == ^tenant_id and is_nil(collection.deleted_at),
        order_by: collection.name
    )
  end

  def get_collection!(tenant_id, id) do
    Repo.get_by!(Collection, id: id, tenant_id: tenant_id)
  end

  @doc """
  Soft-deletes a collection and every source in it, so the whole corpus
  leaves retrieval at once. Each source delete is audited by the existing
  soft-delete path; the collection delete is audited as governance.
  """
  def soft_delete_collection(tenant_id, collection_id, opts \\ []) do
    collection = get_collection!(tenant_id, collection_id)

    source_ids =
      Repo.all(
        from source in Source,
          where:
            source.tenant_id == ^tenant_id and source.collection_id == ^collection_id and
              is_nil(source.deleted_at),
          select: source.id
      )

    # A failed source delete must stop the operation rather than leave a
    # partially deleted corpus behind.
    Enum.each(source_ids, fn source_id ->
      {:ok, _result} = soft_delete_source(tenant_id, source_id)
    end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, collection} =
      collection
      |> Collection.changeset(%{deleted_at: now})
      |> Repo.update()

    record_audit_best_effort(%{
      tenant_id: tenant_id,
      event_kind: "collection_deleted",
      component: "control_panel",
      actor: Keyword.get(opts, :actor, "Admin"),
      status: "deleted",
      summary:
        "Collection \"#{collection.name}\" and #{length(source_ids)} sources were removed from governed memory.",
      metadata: %{collection_id: collection.id, deleted_sources_count: length(source_ids)},
      occurred_at: now
    })

    {:ok, %{collection: collection, deleted_sources_count: length(source_ids)}}
  end

  def list_tenants do
    Repo.all(from tenant in Tenant, order_by: tenant.name)
  end

  def get_tenant!(id), do: Repo.get!(Tenant, id)

  def get_tenant_by_slug(slug), do: Repo.get_by(Tenant, slug: slug)

  def ensure_demo_tenant! do
    get_tenant_by_slug("native-ai") ||
      case create_tenant(%{name: "&native.ai", slug: "native-ai", status: "active"}) do
        {:ok, tenant} -> tenant
        {:error, _changeset} -> get_tenant_by_slug("native-ai")
      end
  end

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def create_agent(tenant_id, attrs) do
    %Agent{tenant_id: tenant_id}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  def list_agents(tenant_id) do
    Repo.all(from agent in Agent, where: agent.tenant_id == ^tenant_id, order_by: agent.name)
  end

  def get_agent(tenant_id, id) do
    Repo.get_by(Agent, id: id, tenant_id: tenant_id)
  end

  def get_agent!(tenant_id, id) do
    Repo.get_by!(Agent, id: id, tenant_id: tenant_id)
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates an agent's base model and per-capability overrides — the
  superadmin-only path. Every change lands on the governance audit trail
  with the before/after models and who made the call.
  """
  def update_agent_model_policy(%Agent{} = agent, attrs, opts \\ []) do
    result =
      agent
      |> Agent.model_policy_changeset(attrs)
      |> Repo.update()

    with {:ok, updated} <- result do
      record_audit_best_effort(%{
        tenant_id: agent.tenant_id,
        agent_id: agent.id,
        event_kind: "model_policy_changed",
        component: "control_panel",
        actor: Keyword.get(opts, :actor, "Superadmin"),
        status: "confirmed",
        summary: "Model policy for #{agent.name} changed.",
        metadata: %{
          agent_name: agent.name,
          previous_model: agent.model,
          model: updated.model,
          previous_overrides: agent.model_policy,
          overrides: updated.model_policy
        },
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      result
    end
  end

  def create_source(tenant_id, attrs) do
    %Source{tenant_id: tenant_id}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_source(tenant_id, attrs) do
    source_type = Map.fetch!(attrs, :source_type)
    source_id = Map.fetch!(attrs, :source_id)

    case get_source_by_external_id(tenant_id, source_type, source_id) do
      nil ->
        create_source(tenant_id, attrs)

      %Source{} = source ->
        source
        |> Source.changeset(attrs)
        |> Repo.update()
    end
  end

  def get_source_by_external_id(tenant_id, source_type, source_id) do
    Repo.get_by(Source, tenant_id: tenant_id, source_type: source_type, source_id: source_id)
  end

  @doc "Active sources created after the given instant (digests, reports)."
  def list_sources_since(tenant_id, %DateTime{} = since) do
    Repo.all(
      from source in Source,
        where:
          source.tenant_id == ^tenant_id and is_nil(source.deleted_at) and
            source.inserted_at > ^since,
        order_by: [desc: source.inserted_at]
    )
  end

  def list_sources(tenant_id) do
    Repo.all(
      from source in Source,
        where: source.tenant_id == ^tenant_id and is_nil(source.deleted_at),
        order_by: [desc: source.updated_at]
    )
  end

  def source_counts_by_type(tenant_id) do
    Source
    |> where([source], source.tenant_id == ^tenant_id and is_nil(source.deleted_at))
    |> group_by([source], source.source_type)
    |> select([source], {source.source_type, count(source.id)})
    |> Repo.all()
    |> Map.new()
  end

  def list_all_sources(tenant_id) do
    Repo.all(
      from source in Source,
        where: source.tenant_id == ^tenant_id,
        order_by: [desc: source.updated_at]
    )
  end

  def get_source!(tenant_id, id) do
    Repo.get_by!(Source, id: id, tenant_id: tenant_id)
  end

  @doc """
  Merges the given settings into a source's settings map and records a
  governance audit event describing the policy change.
  """
  def update_source_settings(tenant_id, source_id, new_settings, opts \\ [])
      when is_map(new_settings) do
    source = get_source!(tenant_id, source_id)
    changes = stringify_keys(new_settings)
    merged = Map.merge(source.settings || %{}, changes)

    with {:ok, updated} <- source |> Source.changeset(%{settings: merged}) |> Repo.update() do
      record_audit_best_effort(%{
        tenant_id: tenant_id,
        source_id: updated.id,
        event_kind: "source_policy_changed",
        component: "control_panel",
        actor: Keyword.get(opts, :actor, "Admin"),
        status: "applied",
        summary: policy_change_summary(updated, changes),
        metadata: %{
          source_type: updated.source_type,
          source_external_id: updated.source_id,
          changed_settings: changes
        },
        citation_url: updated.permalink_or_url,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      {:ok, updated}
    end
  end

  defp policy_change_summary(source, %{"ingest_bot_messages" => enabled}) do
    action = if enabled, do: "now ingests", else: "no longer ingests"
    "#{source.name} #{action} app & bot posts."
  end

  defp policy_change_summary(source, new_settings) do
    keys = new_settings |> Map.keys() |> Enum.map_join(", ", &to_string/1)
    "#{source.name} policy updated: #{keys}."
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  def create_memory_item(tenant_id, %Source{tenant_id: tenant_id} = source, attrs) do
    %Item{tenant_id: tenant_id, source_id: source.id}
    |> Item.changeset(Map.put_new(attrs, :source_type, source.source_type))
    |> Repo.insert()
  end

  def create_memory_item(_tenant_id, _source, _attrs), do: {:error, :invalid_source}

  def list_memory_items(tenant_id) do
    Repo.all(
      from item in Item,
        where: item.tenant_id == ^tenant_id and is_nil(item.deleted_at),
        order_by: [desc: item.inserted_at]
    )
  end

  def count_memory_items(tenant_id) do
    Repo.one(
      from item in Item,
        where: item.tenant_id == ^tenant_id and is_nil(item.deleted_at),
        select: count(item.id)
    )
  end

  @doc "Active (retrievable) memory chunk counts keyed by source id."
  def active_item_counts_by_source(tenant_id) do
    Item
    |> where([item], item.tenant_id == ^tenant_id and is_nil(item.deleted_at))
    |> group_by([item], item.source_id)
    |> select([item], {item.source_id, count(item.id)})
    |> Repo.all()
    |> Map.new()
  end

  def list_source_memory_items(tenant_id, source_id) do
    Repo.all(
      from item in Item,
        where:
          item.tenant_id == ^tenant_id and item.source_id == ^source_id and
            is_nil(item.deleted_at),
        order_by: [asc: item.inserted_at]
    )
  end

  def list_all_source_memory_items(tenant_id, source_id) do
    Repo.all(
      from item in Item,
        where: item.tenant_id == ^tenant_id and item.source_id == ^source_id,
        order_by: [asc: item.inserted_at]
    )
  end

  def soft_delete_source(tenant_id, source_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      source = get_source!(tenant_id, source_id)

      {:ok, source} =
        source
        |> Source.changeset(%{status: "deleted", deleted_at: now})
        |> Repo.update()

      {count, _items} =
        from(item in Item,
          where:
            item.tenant_id == ^tenant_id and item.source_id == ^source.id and
              is_nil(item.deleted_at)
        )
        |> Repo.update_all(set: [deleted_at: now, updated_at: now])

      record_audit_best_effort(%{
        tenant_id: tenant_id,
        source_id: source.id,
        event_kind: "source_deleted",
        component: "memory_service",
        actor: "Memory service",
        status: "deleted",
        summary: "#{source.name} was removed from governed memory.",
        metadata: %{
          source_type: source.source_type,
          source_external_id: source.source_id,
          deleted_items_count: count
        },
        citation_url: source.permalink_or_url,
        occurred_at: now
      })

      %{source: source, deleted_items_count: count}
    end)
  end

  defp record_audit_best_effort(attrs) do
    case Application.get_env(:andnative_ai, :audit_recorder, Audit) do
      recorder when is_function(recorder, 1) -> recorder.(attrs)
      recorder -> recorder.record_best_effort(attrs)
    end
  end
end
