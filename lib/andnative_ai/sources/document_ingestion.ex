defmodule AndnativeAi.Sources.DocumentIngestion do
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Collection
  alias AndnativeAi.Memory.Service

  @allowed_extensions ~w(.md .txt)
  @max_chunk_chars 1_600
  @preview_chars 500

  def ingest_upload(tenant_id, %{path: path, filename: filename}, opts \\ []) do
    collection = Keyword.get(opts, :collection)

    with :ok <- validate_extension(filename),
         {:ok, stored} <- store_file(tenant_id, path, filename),
         {:ok, text} <- File.read(stored.path),
         chunks when chunks != [] <- chunk_text(text),
         {:ok, result} <-
           Service.ingest(
             tenant_id,
             %{
               source_type: "document",
               source_id: stored.id,
               name: filename,
               permalink_or_url: stored.url,
               collection_id: collection && collection.id
             },
             Enum.map(chunks, fn chunk ->
               %{
                 text: Collection.context_prefix(collection, filename) <> chunk,
                 provenance: %{
                   "filename" => filename,
                   "stored_path" => stored.path,
                   "permalink" => stored.url
                 }
               }
             end),
             %{"filename" => filename, "stored_path" => stored.path},
             "tenant",
             "default"
           ) do
      {:ok, Map.put(result, :stored_path, stored.path)}
    else
      [] -> {:error, :empty_document}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Staged multi-file uploads (collections)

  @doc """
  Copies an uploaded file into a staging directory, expanding `.zip`
  archives. Returns `{:ok, [%{path, filename, preview}]}` for the usable
  documents found. Staged files live outside governed memory until
  `ingest_staged/3` confirms them.
  """
  def stage_upload(staging_dir, %{path: path, filename: filename}) do
    File.mkdir_p!(staging_dir)

    if Path.extname(filename) == ".zip" do
      expand_zip(staging_dir, path)
    else
      with :ok <- validate_extension(filename) do
        destination = Path.join(staging_dir, sanitize_filename(filename))

        with {:ok, _bytes} <- File.copy(path, destination) do
          {:ok, [staged_entry(destination, filename)]}
        end
      end
    end
  end

  @doc "Ingests every staged file into the given collection, then cleans up."
  def ingest_staged(tenant_id, staged_files, collection) do
    results =
      Enum.map(staged_files, fn staged ->
        {staged.filename,
         ingest_upload(tenant_id, %{path: staged.path, filename: staged.filename},
           collection: collection
         )}
      end)

    {succeeded, failed} =
      Enum.split_with(results, fn {_filename, result} -> match?({:ok, _}, result) end)

    %{succeeded: length(succeeded), failed: Enum.map(failed, fn {name, _} -> name end)}
  end

  def discard_staged(staging_dir), do: File.rm_rf(staging_dir)

  defp expand_zip(staging_dir, zip_path) do
    extract_dir = Path.join(staging_dir, "zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(extract_dir)

    case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(extract_dir)) do
      {:ok, entries} ->
        staged =
          entries
          |> Enum.map(&to_string/1)
          |> Enum.filter(&safe_zip_entry?(&1, extract_dir))
          |> Enum.map(&staged_entry(&1, Path.basename(&1)))

        if staged == [], do: {:error, :empty_archive}, else: {:ok, staged}

      {:error, reason} ->
        {:error, {:invalid_zip, reason}}
    end
  end

  defp safe_zip_entry?(path, extract_dir) do
    inside? = String.starts_with?(Path.expand(path), Path.expand(extract_dir))
    hidden? = path |> Path.basename() |> String.starts_with?(".")
    inside? and not hidden? and Path.extname(path) in @allowed_extensions and File.regular?(path)
  end

  defp staged_entry(path, filename) do
    preview =
      case File.read(path) do
        {:ok, text} -> String.slice(text, 0, @preview_chars)
        _unreadable -> ""
      end

    %{path: path, filename: filename, preview: preview}
  end

  def delete_source(tenant_id, source_id), do: Service.delete_source(tenant_id, source_id)

  def list_uploaded_sources(tenant_id), do: Memory.list_sources(tenant_id)

  def chunk_text(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split(~r/(?=^\#{1,6}\s+)/m, trim: true)
    |> Enum.flat_map(&split_large_section/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_large_section(section) do
    paragraphs = String.split(section, ~r/\n{2,}/, trim: true)

    {chunks, current} =
      Enum.reduce(paragraphs, {[], ""}, fn paragraph, {chunks, current} ->
        candidate = join_chunk(current, paragraph)

        cond do
          String.length(candidate) <= @max_chunk_chars ->
            {chunks, candidate}

          current == "" ->
            {chunks ++ hard_wrap(paragraph), ""}

          true ->
            {chunks ++ [current], paragraph}
        end
      end)

    if current == "", do: chunks, else: chunks ++ [current]
  end

  defp hard_wrap(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(@max_chunk_chars)
    |> Enum.map(&Enum.join/1)
  end

  defp join_chunk("", paragraph), do: paragraph
  defp join_chunk(current, paragraph), do: current <> "\n\n" <> paragraph

  defp validate_extension(filename) do
    if Path.extname(filename) in @allowed_extensions do
      :ok
    else
      {:error, :unsupported_file_type}
    end
  end

  defp store_file(tenant_id, source_path, filename) do
    id = Ecto.UUID.generate()
    safe_filename = sanitize_filename(filename)
    directory = Path.join([raw_sources_path(), to_string(tenant_id)])
    destination = Path.join(directory, "#{id}-#{safe_filename}")

    with :ok <- File.mkdir_p(directory),
         {:ok, _bytes} <- File.copy(source_path, destination) do
      {:ok, %{id: id, path: destination, url: "file://" <> destination}}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "-")
  end

  defp raw_sources_path do
    Application.get_env(:andnative_ai, :raw_sources_path) ||
      System.get_env("RAW_SOURCES_PATH") ||
      "var/sources"
  end
end
