defmodule AndnativeAi.Memory do
  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Memory.{Agent, Item, Source, Tenant}
  alias AndnativeAi.Runtime.Audit

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

  def get_agent!(tenant_id, id) do
    Repo.get_by!(Agent, id: id, tenant_id: tenant_id)
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
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
