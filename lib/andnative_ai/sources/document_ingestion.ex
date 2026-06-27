defmodule AndnativeAi.Sources.DocumentIngestion do
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service

  @allowed_extensions ~w(.md .txt)
  @max_chunk_chars 1_600

  def ingest_upload(tenant_id, %{path: path, filename: filename}) do
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
               permalink_or_url: stored.url
             },
             Enum.map(chunks, fn chunk ->
               %{
                 text: chunk,
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
