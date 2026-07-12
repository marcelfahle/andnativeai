defmodule AndnativeAi.Memory.RetrievalQualityTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.{Embeddings, Service, SituateWorker}

  defmodule FakeOpenAI do
    def response(%{input: input}) do
      # Deterministic "situating": echo which chunk this is.
      if input =~ "manager approval" do
        {:ok, "From the employee handbook; covers reimbursement approval thresholds."}
      else
        {:ok, "From the employee handbook; covers general onboarding."}
      end
    end
  end

  defmodule ExplodingProvider do
    def embed(_text), do: raise("provider should not be called in this test")
  end

  setup do
    Application.put_env(:andnative_ai, :openai_client, FakeOpenAI)
    previous_provider = Application.get_env(:andnative_ai, :embeddings_provider)
    previous_key = System.get_env("OPENAI_API_KEY")

    on_exit(fn ->
      Application.delete_env(:andnative_ai, :openai_client)

      if previous_provider,
        do: Application.put_env(:andnative_ai, :embeddings_provider, previous_provider),
        else: Application.delete_env(:andnative_ai, :embeddings_provider)

      if previous_key,
        do: System.put_env("OPENAI_API_KEY", previous_key),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "Quality #{System.unique_integer([:positive])}",
        slug: "quality-#{System.unique_integer([:positive])}",
        status: "active"
      })

    %{tenant: tenant}
  end

  test "embedding provider is config-driven with a deterministic default" do
    assert Embeddings.provider() == Embeddings.Deterministic
    assert Embeddings.provider_label() =~ "deterministic"

    Application.put_env(:andnative_ai, :embeddings_provider, ExplodingProvider)
    assert Embeddings.provider() == ExplodingProvider
  end

  test "situate worker adds context and re-embeds document chunks", %{tenant: tenant} do
    System.put_env("OPENAI_API_KEY", "sk-test")
    assert SituateWorker.enabled?()

    {:ok, %{source: source, items: [item]}} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "situate-1",
          name: "handbook.md",
          permalink_or_url: "https://example.com/handbook"
        },
        ["Reimbursements above 500 need manager approval."],
        %{"filename" => "handbook.md"},
        "tenant",
        "default"
      )

    original_embedding = item.embedding

    assert :ok =
             SituateWorker.perform(%Oban.Job{
               args: %{"tenant_id" => tenant.id, "source_id" => source.id}
             })

    [updated] = Memory.list_source_memory_items(tenant.id, source.id)
    assert updated.context =~ "reimbursement approval thresholds"
    assert updated.embedding != original_embedding

    # Search still finds the chunk; raw text is untouched.
    [result | _] = Service.search(tenant.id, "manager approval reimbursements", %{limit: 3})
    assert result.text == "Reimbursements above 500 need manager approval."
  end

  test "reembed_all re-embeds active items with the current provider", %{tenant: tenant} do
    {:ok, %{source: source}} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "reembed-1",
          name: "doc.md",
          permalink_or_url: "https://example.com/doc"
        },
        ["A fact worth re-embedding."],
        %{"filename" => "doc.md"},
        "tenant",
        "default"
      )

    assert SituateWorker.reembed_all(tenant.id) == 1

    [item] = Memory.list_source_memory_items(tenant.id, source.id)
    assert Service.search(tenant.id, "fact worth re-embedding", %{limit: 3}) != []
    assert item.deleted_at == nil
  end
end
