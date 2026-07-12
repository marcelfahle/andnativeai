defmodule AndnativeAiWeb.SourceReaderHTML do
  use AndnativeAiWeb, :html

  def show(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-6 py-10">
      <header class="border-b border-base-300 pb-6">
        <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">
          <span :if={@collection}>{@collection.name} · </span>Governed source
        </p>
        <h1 class="mt-1 text-2xl font-semibold">{@source.name}</h1>
        <p :if={@source.last_ingested_at} class="mt-1 text-xs text-base-content/60">
          Last ingested {Calendar.strftime(@source.last_ingested_at, "%Y-%m-%d %H:%M UTC")}
        </p>
      </header>
      <article id="source-document" class="prose prose-sm mt-8 max-w-none">
        {Phoenix.HTML.raw(@document_html)}
      </article>
      <footer class="mt-10 border-t border-base-300 pt-4 text-xs text-base-content/50">
        <.link navigate={~p"/admin/memory"} class="link">Memory map</.link>
        · Served from governed memory.
      </footer>
    </div>
    """
  end
end
