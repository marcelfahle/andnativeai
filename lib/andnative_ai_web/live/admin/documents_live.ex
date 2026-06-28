defmodule AndnativeAiWeb.Admin.DocumentsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Sources.DocumentIngestion

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    socket =
      socket
      |> assign(:page_title, "Sources")
      |> assign(:tenant, tenant)
      |> assign(:form, to_form(%{}, as: :upload))
      |> reload_sources()
      |> allow_upload(:document,
        accept: ~w(.md .txt),
        max_entries: 1,
        max_file_size: 2_000_000,
        auto_upload: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        case DocumentIngestion.ingest_upload(socket.assigns.tenant.id, %{
               path: path,
               filename: entry.client_name
             }) do
          {:ok, result} -> {:ok, result.source.id}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    socket =
      case results do
        [] ->
          put_flash(socket, :error, "Choose a Markdown or text file first.")

        [_source_id | _] ->
          socket
          |> put_flash(:info, "Document ingested.")
          |> reload_sources()
      end

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    source_id = String.to_integer(id)

    socket =
      case DocumentIngestion.delete_source(socket.assigns.tenant.id, source_id) do
        {:ok, _result} ->
          socket
          |> put_flash(:info, "Source deleted.")
          |> reload_sources()

        {:error, _reason} ->
          put_flash(socket, :error, "Source could not be deleted.")
      end

    {:noreply, socket}
  end

  defp reload_sources(socket) do
    all_sources = DocumentIngestion.list_uploaded_sources(socket.assigns.tenant.id)
    document_sources = Enum.filter(all_sources, &(&1.source_type == "document"))
    slack_sources = Enum.filter(all_sources, &(&1.source_type == "slack_channel"))

    socket
    |> assign(:sources, document_sources)
    |> assign(:slack_sources, slack_sources)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-5xl space-y-8">
        <section class="flex flex-col gap-2 border-b border-base-300 pb-6 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
            <h1 class="text-3xl font-semibold tracking-normal text-base-content">Sources</h1>
          </div>
        </section>

        <section class="grid gap-6 lg:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]">
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <h2 class="text-base font-semibold">Upload document</h2>

            <.form
              for={@form}
              id="document-upload-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-5 space-y-4"
            >
              <div class="rounded-lg border border-dashed border-base-300 bg-base-200/60 p-5">
                <.live_file_input
                  upload={@uploads.document}
                  class="file-input file-input-bordered w-full"
                />

                <div class="mt-4 space-y-2">
                  <div :for={entry <- @uploads.document.entries} id={"upload-entry-#{entry.ref}"}>
                    <div class="flex items-center justify-between gap-3 text-sm">
                      <span class="truncate font-medium">{entry.client_name}</span>
                      <span class="tabular-nums text-base-content/60">{entry.progress}%</span>
                    </div>
                    <progress
                      class="progress progress-primary mt-2 h-1.5"
                      value={entry.progress}
                      max="100"
                    >
                    </progress>
                  </div>
                </div>
              </div>

              <div class="flex items-center justify-end">
                <button id="document-upload-submit" class="btn btn-primary">
                  <.icon name="hero-arrow-up-tray" class="size-4" /> Ingest
                </button>
              </div>
            </.form>
          </div>

          <div class="rounded-lg border border-base-300 bg-base-100">
            <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
              <h2 class="text-base font-semibold">Documents</h2>
              <span class="badge badge-neutral">{length(@sources)}</span>
            </div>

            <div id="document-sources" class="divide-y divide-base-300">
              <div
                :if={@sources == []}
                id="document-sources-empty"
                class="px-5 py-10 text-sm text-base-content/60"
              >
                No uploaded sources.
              </div>

              <div
                :for={source <- @sources}
                id={"source-#{source.id}"}
                class="flex items-center justify-between gap-4 px-5 py-4"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium">{source.name}</p>
                  <p class="mt-1 truncate text-xs text-base-content/60">{source.permalink_or_url}</p>
                  <div class="mt-2 flex flex-wrap items-center gap-2 text-xs">
                    <span class="badge badge-outline">{source.status}</span>
                    <span :if={source.last_ingested_at} class="text-base-content/50">
                      {Calendar.strftime(source.last_ingested_at, "%Y-%m-%d %H:%M UTC")}
                    </span>
                  </div>
                </div>

                <button
                  id={"delete-source-#{source.id}"}
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="delete"
                  phx-value-id={source.id}
                  data-confirm="Delete this source from memory?"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          </div>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">Slack channels</h2>
            <span class="badge badge-neutral">{length(@slack_sources)}</span>
          </div>
          <div id="slack-source-list" class="divide-y divide-base-300">
            <div
              :if={@slack_sources == []}
              id="slack-sources-empty"
              class="px-5 py-10 text-sm text-base-content/60"
            >
              No Slack channels.
            </div>
            <div
              :for={source <- @slack_sources}
              id={"source-#{source.id}"}
              class="flex items-center justify-between gap-4 px-5 py-4"
            >
              <div class="min-w-0">
                <p class="truncate font-medium">{source.name}</p>
                <p class="mt-1 truncate text-xs text-base-content/60">{source.source_id}</p>
                <span class="mt-2 badge badge-outline">{source.status}</span>
              </div>
              <button
                id={"delete-source-#{source.id}"}
                class="btn btn-ghost btn-sm text-error"
                phx-click="delete"
                phx-value-id={source.id}
                data-confirm="Delete this source from memory?"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
