defmodule AndnativeAiWeb.Admin.DocumentsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Collection
  alias AndnativeAi.Sources.CollectionClassifier
  alias AndnativeAi.Sources.DocumentIngestion

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    socket =
      socket
      |> assign(:page_title, "Sources")
      |> assign(:tenant, tenant)
      |> assign(:form, to_form(%{}, as: :upload))
      |> assign(:staging_dir, nil)
      |> assign(:staged_files, [])
      |> assign(:suggested_name, nil)
      |> assign(:collection_form, nil)
      |> reload_sources()
      |> allow_upload(:document,
        accept: ~w(.md .txt),
        max_entries: 1,
        max_file_size: 2_000_000,
        auto_upload: false
      )
      |> allow_upload(:collection_docs,
        accept: ~w(.md .txt .zip),
        max_entries: 40,
        max_file_size: 20_000_000,
        auto_upload: true,
        progress: &handle_collection_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:staging_dir] do
      DocumentIngestion.discard_staged(socket.assigns.staging_dir)
    end

    :ok
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("validate-collection", _params, socket), do: {:noreply, socket}

  def handle_event("stage-collection", _params, socket) do
    staged = socket.assigns.staged_files

    if staged == [] do
      {:noreply,
       put_flash(socket, :error, "No usable documents found. Upload .md/.txt files or a .zip.")}
    else
      proposal = CollectionClassifier.propose(staged, socket.assigns.suggested_name)

      {:noreply,
       assign(
         socket,
         :collection_form,
         to_form(
           %{
             "name" => proposal.name,
             "kind" => proposal.kind,
             "description" => proposal.description
           },
           as: :collection
         )
       )}
    end
  end

  def handle_event("confirm-collection", %{"collection" => params}, socket) do
    actor = (socket.assigns.current_user && socket.assigns.current_user.email) || "Admin"

    case Memory.create_collection(socket.assigns.tenant.id, params, actor: actor) do
      {:ok, collection} ->
        result =
          DocumentIngestion.ingest_staged(
            socket.assigns.tenant.id,
            socket.assigns.staged_files,
            collection
          )

        DocumentIngestion.discard_staged(socket.assigns.staging_dir)

        message =
          case result do
            %{succeeded: ok, failed: []} ->
              "Collection \"#{collection.name}\" created with #{ok} documents."

            %{succeeded: ok, failed: failed} ->
              "Collection \"#{collection.name}\" created with #{ok} documents; skipped: #{Enum.join(failed, ", ")}."
          end

        {:noreply,
         socket
         |> assign(:staging_dir, nil)
         |> assign(:staged_files, [])
         |> assign(:suggested_name, nil)
         |> assign(:collection_form, nil)
         |> put_flash(:info, message)
         |> reload_sources()}

      {:error, changeset} ->
        {:noreply, assign(socket, :collection_form, to_form(changeset, as: :collection))}
    end
  end

  def handle_event("discard-collection", _params, socket) do
    if socket.assigns.staging_dir do
      DocumentIngestion.discard_staged(socket.assigns.staging_dir)
    end

    {:noreply,
     socket
     |> assign(:staging_dir, nil)
     |> assign(:staged_files, [])
     |> assign(:suggested_name, nil)
     |> assign(:collection_form, nil)}
  end

  def handle_event("delete-collection", %{"id" => id}, socket) do
    case Integer.parse(to_string(id)) do
      {collection_id, ""} ->
        actor = (socket.assigns.current_user && socket.assigns.current_user.email) || "Admin"

        {:ok, %{collection: collection, deleted_sources_count: count}} =
          Memory.soft_delete_collection(socket.assigns.tenant.id, collection_id, actor: actor)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Collection \"#{collection.name}\" deleted; #{count} sources left retrieval."
         )
         |> reload_sources()}

      _invalid ->
        {:noreply, socket}
    end
  end

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

  def handle_event("toggle-bot-ingestion", %{"id" => id}, socket) do
    source_id = String.to_integer(id)
    tenant_id = socket.assigns.tenant.id
    source = Memory.get_source!(tenant_id, source_id)
    enabled? = not AndnativeAi.Memory.Source.ingest_bot_messages?(source)
    actor = socket.assigns.current_user && socket.assigns.current_user.email

    socket =
      case Memory.update_source_settings(
             tenant_id,
             source_id,
             %{"ingest_bot_messages" => enabled?},
             actor: actor || "Admin"
           ) do
        {:ok, _source} ->
          message =
            if enabled?,
              do: "App & bot posts will now be ingested for this channel.",
              else: "App & bot posts are no longer ingested for this channel."

          socket
          |> put_flash(:info, message)
          |> reload_sources()

        {:error, _reason} ->
          put_flash(socket, :error, "Could not update the channel policy.")
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
    tenant_id = socket.assigns.tenant.id
    all_sources = DocumentIngestion.list_uploaded_sources(tenant_id)
    document_sources = Enum.filter(all_sources, &(&1.source_type == "document"))
    slack_sources = Enum.filter(all_sources, &(&1.source_type == "slack_channel"))

    collections = Memory.list_collections(tenant_id)
    counts_by_collection = Enum.frequencies_by(document_sources, & &1.collection_id)

    socket
    |> assign(:sources, document_sources)
    |> assign(:slack_sources, slack_sources)
    |> assign(:collections, collections)
    |> assign(:collection_counts, counts_by_collection)
  end

  # Stages each collection upload as soon as it finishes transferring, so
  # the review step never has to consume many entries at once.
  defp handle_collection_progress(:collection_docs, entry, socket) do
    if entry.done? do
      staging_dir =
        socket.assigns.staging_dir ||
          Path.join(System.tmp_dir!(), "andnative-staging-#{System.unique_integer([:positive])}")

      # The callback wraps the stage result in {:ok, _} because that is the
      # consume contract; consume_uploaded_entry unwraps exactly that layer
      # and hands back stage_upload's own {:ok, files} | {:error, reason}.
      stage_result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          stage_result =
            DocumentIngestion.stage_upload(staging_dir, %{
              path: path,
              filename: entry.client_name
            })

          {:ok, stage_result}
        end)

      socket =
        case stage_result do
          {:ok, files} when is_list(files) ->
            socket
            |> assign(:staging_dir, staging_dir)
            |> update(:staged_files, &(&1 ++ files))
            |> update(:suggested_name, &(&1 || suggestion_from(entry.client_name)))

          _error ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp suggestion_from(client_name) do
    case Path.extname(client_name) do
      ".zip" ->
        client_name
        |> Path.basename(".zip")
        |> String.replace(~r/[-_]+/, " ")
        |> String.trim()
        |> :string.titlecase()

      _other ->
        nil
    end
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

        <section id="collection-builder" class="rounded-lg border border-base-300 bg-base-100 p-5">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-base font-semibold">New collection</h2>
            <p class="text-xs text-base-content/50">
              A collection tells the agent what a corpus <span class="italic">is</span>
              — answers cite it, retrieval can scope to it, deletion removes it whole.
            </p>
          </div>

          <.form
            :if={is_nil(@collection_form)}
            for={@form}
            id="collection-upload-form"
            phx-change="validate-collection"
            phx-submit="stage-collection"
            class="mt-4 space-y-4"
          >
            <div class="rounded-lg border border-dashed border-base-300 bg-base-200/60 p-5">
              <.live_file_input
                upload={@uploads.collection_docs}
                class="file-input file-input-bordered w-full"
              />
              <p class="mt-2 text-xs text-base-content/50">
                Select multiple .md/.txt files, or upload a whole folder as a .zip —
                the folder name becomes the proposed collection name.
              </p>

              <div class="mt-4 space-y-1">
                <div
                  :for={entry <- @uploads.collection_docs.entries}
                  id={"collection-entry-#{entry.ref}"}
                  class="flex items-center justify-between gap-3 text-sm"
                >
                  <span class="truncate">{entry.client_name}</span>
                  <span class="tabular-nums text-base-content/50">{entry.progress}%</span>
                </div>
              </div>

              <p
                :if={@staged_files != []}
                id="collection-staged-count"
                class="mt-3 text-xs text-base-content/60"
              >
                {length(@staged_files)} documents staged and ready for review.
              </p>
            </div>

            <div class="flex items-center justify-end">
              <button id="collection-stage-submit" class="btn btn-primary">
                <.icon name="hero-folder-plus" class="size-4" /> Review collection
              </button>
            </div>
          </.form>

          <div :if={@collection_form} id="collection-proposal" class="mt-4 space-y-4">
            <div class="rounded-lg border border-base-300 bg-base-200/50 px-4 py-3">
              <p class="text-xs font-semibold uppercase tracking-wider text-base-content/45">
                Proposed — confirm or edit before anything enters memory
              </p>
              <p class="mt-1.5 text-sm text-base-content/70">
                {length(@staged_files)} documents staged: {@staged_files
                |> Enum.take(6)
                |> Enum.map_join(", ", & &1.filename)}<span :if={length(@staged_files) > 6}> and {length(@staged_files) - 6} more</span>.
              </p>
            </div>

            <.form
              for={@collection_form}
              id="collection-confirm-form"
              phx-submit="confirm-collection"
              class="space-y-4"
            >
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@collection_form[:name]} type="text" label="Collection name" />
                <.input
                  field={@collection_form[:kind]}
                  type="select"
                  label="Kind"
                  options={Collection.kinds() -- ["conversation"]}
                />
              </div>
              <.input
                field={@collection_form[:description]}
                type="textarea"
                label="What is this corpus? (used as retrieval context)"
              />

              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  id="collection-discard"
                  phx-click="discard-collection"
                  class="btn btn-ghost"
                >
                  Discard
                </button>
                <button id="collection-confirm-submit" class="btn btn-primary">
                  <.icon name="hero-check" class="size-4" /> Confirm &amp; ingest
                </button>
              </div>
            </.form>
          </div>
        </section>

        <section
          :if={@collections != []}
          id="collections-list"
          class="rounded-lg border border-base-300 bg-base-100"
        >
          <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">Collections</h2>
            <span class="text-xs tabular-nums text-base-content/50">{length(@collections)}</span>
          </div>
          <div class="divide-y divide-base-300/70">
            <div
              :for={collection <- @collections}
              id={"collection-#{collection.id}"}
              class="flex items-center justify-between gap-4 px-5 py-3"
            >
              <div class="min-w-0">
                <div class="flex flex-wrap items-baseline gap-2">
                  <p class="truncate text-sm font-medium">{collection.name}</p>
                  <span class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50">
                    {collection.kind}
                  </span>
                  <span class="text-xs tabular-nums text-base-content/50">
                    {Map.get(@collection_counts, collection.id, 0)} documents
                  </span>
                </div>
                <p class="mt-1 line-clamp-2 text-xs text-base-content/55">
                  {collection.description}
                </p>
              </div>
              <button
                id={"delete-collection-#{collection.id}"}
                class="btn btn-ghost btn-sm text-error"
                phx-click="delete-collection"
                phx-value-id={collection.id}
                data-confirm="Delete this collection and remove all its documents from memory?"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
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
                <div class="mt-2 flex flex-wrap items-center gap-2">
                  <span class="badge badge-outline">{source.status}</span>
                  <span
                    :if={AndnativeAi.Memory.Source.ingest_bot_messages?(source)}
                    class="badge badge-info badge-outline"
                  >
                    app posts on
                  </span>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <label
                  class="flex cursor-pointer items-center gap-2 text-xs text-base-content/70"
                  title="Ingest app & bot posts (Linear updates and similar) from this channel"
                >
                  <input
                    type="checkbox"
                    id={"toggle-bot-ingestion-#{source.id}"}
                    class="toggle toggle-sm"
                    checked={AndnativeAi.Memory.Source.ingest_bot_messages?(source)}
                    phx-click="toggle-bot-ingestion"
                    phx-value-id={source.id}
                  />
                  <span class="hidden sm:inline">App &amp; bot posts</span>
                </label>
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
      </div>
    </Layouts.app>
    """
  end
end
