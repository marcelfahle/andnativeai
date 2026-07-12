defmodule AndnativeAi.Memory.Citations do
  @moduledoc """
  Builds the public URLs cited in Slack answers. Document citations always
  point at the governed memory map — computed at citation time so stale
  `file://` permalinks stored before this existed can never resurface.
  """

  def document_url(source_id) do
    "#{public_base_url()}/admin/memory#memory-source-#{source_id}"
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
