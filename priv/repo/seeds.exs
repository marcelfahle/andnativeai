# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     AndnativeAi.Repo.insert!(%AndnativeAi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias AndnativeAi.Memory

case Memory.get_tenant_by_slug("native-ai") do
  nil ->
    {:ok, _tenant} =
      Memory.create_tenant(%{
        name: "&native.ai",
        slug: "native-ai",
        status: "active"
      })

  _tenant ->
    :ok
end
