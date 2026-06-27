defmodule AndnativeAi.Memory do
  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Memory.{Agent, Item, Source, Tenant}

  def list_tenants do
    Repo.all(from tenant in Tenant, order_by: tenant.name)
  end

  def get_tenant!(id), do: Repo.get!(Tenant, id)

  def get_tenant_by_slug(slug), do: Repo.get_by(Tenant, slug: slug)

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

  def list_sources(tenant_id) do
    Repo.all(
      from source in Source,
        where: source.tenant_id == ^tenant_id and is_nil(source.deleted_at),
        order_by: [desc: source.updated_at]
    )
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

      %{source: source, deleted_items_count: count}
    end)
  end
end
