defmodule AndnativeAi.Memory.Citations do
  @moduledoc """
  Builds the public URLs cited in Slack answers. Document citations point
  at the source reader whenever the stored permalink is missing or a
  useless `file://` path (see `Memory.Service.override_document_citation/1`);
  genuine web permalinks are kept as stored.
  """

  def document_url(source_id) do
    "#{public_base_url()}/sources/#{source_id}"
  end

  # Derives the base URL from the endpoint's :url config (the same values
  # runtime.exs sets from PHX_HOST) without requiring the endpoint process,
  # so Release tasks can build citation URLs too.
  def public_base_url do
    url = Application.get_env(:andnative_ai, AndnativeAiWeb.Endpoint, [])[:url] || []
    host = Keyword.get(url, :host, "localhost")
    scheme = Keyword.get(url, :scheme, if(host == "localhost", do: "http", else: "https"))
    port = Keyword.get(url, :port, if(host == "localhost", do: 4000, else: nil))

    case {scheme, port} do
      {_scheme, nil} -> "#{scheme}://#{host}"
      {"https", 443} -> "#{scheme}://#{host}"
      {"http", 80} -> "#{scheme}://#{host}"
      {_scheme, port} -> "#{scheme}://#{host}:#{port}"
    end
  end
end
