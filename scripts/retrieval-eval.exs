# Retrieval quality eval: ingests the demo handbook fixture and measures
# top-3 hit rate for a small question set. Run against different embedding
# providers to compare:
#
#   DATABASE_PORT=55432 mix run scripts/retrieval-eval.exs                # deterministic
#   OPENAI_API_KEY=sk-... DATABASE_PORT=55432 mix run scripts/retrieval-eval.exs
#
# The eval tenant is recreated on every run.

alias AndnativeAi.Memory
alias AndnativeAi.Memory.Embeddings
alias AndnativeAi.Memory.Service
alias AndnativeAi.Repo

import Ecto.Query

slug = "retrieval-eval"

case Memory.get_tenant_by_slug(slug) do
  nil -> :ok
  tenant -> Repo.delete_all(from t in AndnativeAi.Memory.Tenant, where: t.id == ^tenant.id)
end

{:ok, tenant} = Memory.create_tenant(%{name: "Retrieval Eval", slug: slug, status: "active"})

{:ok, _} =
  Service.ingest(
    tenant.id,
    %{
      source_type: "document",
      source_id: "eval-handbook",
      name: "handbook.md",
      permalink_or_url: "file://priv/fixtures/demo/handbook.md"
    },
    AndnativeAi.Sources.DocumentIngestion.chunk_text(File.read!("priv/fixtures/demo/handbook.md")),
    %{"filename" => "handbook.md"},
    "tenant",
    "default"
  )

questions = [
  {"when do reimbursements need manager approval?", "handbook.md"},
  {"who approves reimbursements above 500?", "handbook.md"},
  {"what does the launch policy require?", "handbook.md"},
  {"do demo answers need citations?", "handbook.md"},
  {"what is required before using OpenClaw for the pilot?", "handbook.md"}
]

hits =
  Enum.count(questions, fn {question, expected_source} ->
    results = Service.search(tenant.id, question, %{limit: 3})
    hit? = Enum.any?(results, &(&1.source.name == expected_source))
    status = if hit?, do: "HIT ", else: "MISS"
    IO.puts("#{status} #{question}")
    hit?
  end)

IO.puts("")
IO.puts("Provider: #{Embeddings.provider_label()}")
IO.puts("Top-3 hit rate: #{hits}/#{length(questions)}")
