import Ecto.Query

alias AndnativeAi.Memory
alias AndnativeAi.Memory.{Item, Source}
alias AndnativeAi.Repo

tenant = Memory.ensure_demo_tenant!()

{item_count, _} =
  from(item in Item, where: item.tenant_id == ^tenant.id)
  |> Repo.delete_all()

{source_count, _} =
  from(source in Source, where: source.tenant_id == ^tenant.id)
  |> Repo.delete_all()

IO.puts("Deleted #{item_count} memory items and #{source_count} sources for #{tenant.slug}.")
