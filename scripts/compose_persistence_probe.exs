alias AndnativeAi.Memory
alias AndnativeAi.Memory.Service

tenant = Memory.ensure_demo_tenant!()

case System.argv() do
  ["seed"] ->
    {:ok, _result} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "compose-persistence",
          name: "compose-persistence.txt",
          permalink_or_url: "file://compose-persistence.txt"
        },
        ["Compose persistence probe memory survives a restart."],
        %{"permalink" => "file://compose-persistence.txt"},
        "tenant",
        "default"
      )

    IO.puts("Seeded compose persistence probe.")

  ["assert"] ->
    case Service.search(tenant.id, "compose persistence restart", %{limit: 3}) do
      [%{source: %{external_id: "compose-persistence"}} | _] ->
        IO.puts("Compose persistence probe found.")

      results ->
        raise "Compose persistence probe missing: #{inspect(results)}"
    end

  other ->
    raise "Expected seed or assert, got: #{inspect(other)}"
end
