defmodule AndnativeAi.Slack.MessageText do
  @moduledoc """
  Normalizes Slack message payloads into plain searchable text.

  Human messages usually carry everything in `text`. App and bot posts
  (Linear, GitHub, and similar notification apps) often ship an empty or
  minimal `text` with the useful content inside `blocks` and `attachments`.
  This module flattens those structures into one normalized string and
  detects Linear issue notifications so their fields survive distillation.
  """

  @linear_url ~r/https?:\/\/linear\.app\/[^\s|>)]+/

  @doc """
  Returns true when the message was authored by an app or bot rather than a
  human member, based on `bot_id`, `bot_profile`, or the `bot_message` subtype.
  """
  def app_message?(%{"subtype" => "bot_message"}), do: true
  def app_message?(%{"bot_id" => bot_id}) when is_binary(bot_id) and bot_id != "", do: true
  def app_message?(%{"bot_profile" => %{}}), do: true
  def app_message?(_message), do: false

  @doc """
  Returns true when the message was authored by this workspace's own bot
  user, either directly or through its bot profile.
  """
  def self_authored?(message, bot_user_id) when is_binary(bot_user_id) and bot_user_id != "" do
    message["user"] == bot_user_id or
      get_in(message, ["bot_profile", "user_id"]) == bot_user_id
  end

  def self_authored?(_message, _bot_user_id), do: false

  @doc """
  Extracts one normalized text string from `text`, `blocks`, and
  `attachments`. Returns `""` when nothing usable is present.
  """
  def extract(message) when is_map(message) do
    [
      text_part(message["text"]),
      blocks_text(message["blocks"]),
      attachments_text(message["attachments"])
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(" ")
    |> squeeze()
  end

  def extract(_message), do: ""

  @doc """
  Normalizes a message for ingestion. App/bot messages get their blocks and
  attachments flattened into `text` and are tagged with `"app_message" => true`
  so the distiller treats curated notifications as durable content. Linear
  notifications additionally get a structured summary and the Linear issue URL
  in provenance-friendly fields.
  """
  def normalize(message) when is_map(message) do
    if app_message?(message) do
      text = extract(message)

      message
      |> Map.put("text", linear_prefix(message) <> text)
      |> Map.put("app_message", true)
      |> put_linear_url(text)
    else
      message
    end
  end

  def normalize(message), do: message

  @doc """
  Returns true when the message looks like a Linear issue notification.
  """
  def linear_message?(message) when is_map(message) do
    app_message?(message) and
      (linear_bot_profile?(message) or Regex.match?(@linear_url, extract(message)))
  end

  def linear_message?(_message), do: false

  defp linear_bot_profile?(message) do
    name =
      get_in(message, ["bot_profile", "name"]) ||
        message["username"] ||
        ""

    name |> to_string() |> String.downcase() |> String.contains?("linear")
  end

  defp linear_prefix(message) do
    if linear_message?(message), do: "Linear update: ", else: ""
  end

  defp put_linear_url(message, text) do
    case Regex.run(@linear_url, text) do
      [url | _] -> Map.put(message, "app_link", url)
      _ -> message
    end
  end

  defp text_part(text) when is_binary(text), do: text |> unescape_mrkdwn() |> squeeze()
  defp text_part(_text), do: ""

  defp blocks_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&block_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp blocks_text(_blocks), do: ""

  defp block_text(%{"type" => "section"} = block) do
    [
      element_text(block["text"]),
      fields_text(block["fields"])
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp block_text(%{"type" => "header"} = block), do: element_text(block["text"])

  defp block_text(%{"type" => "context"} = block) do
    block["elements"]
    |> List.wrap()
    |> Enum.map(&element_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp block_text(%{"type" => "rich_text"} = block) do
    block["elements"]
    |> List.wrap()
    |> Enum.map(&rich_text_element/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp block_text(_block), do: ""

  defp rich_text_element(%{"elements" => elements}) do
    elements
    |> List.wrap()
    |> Enum.map(&rich_text_element/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp rich_text_element(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp rich_text_element(%{"type" => "link"} = element), do: link_text(element)
  defp rich_text_element(_element), do: ""

  defp link_text(%{"text" => text, "url" => url}) when is_binary(text) and is_binary(url),
    do: "#{text} (#{url})"

  defp link_text(%{"url" => url}) when is_binary(url), do: url
  defp link_text(_element), do: ""

  defp element_text(%{"text" => text}) when is_binary(text), do: unescape_mrkdwn(text)
  defp element_text(text) when is_binary(text), do: unescape_mrkdwn(text)
  defp element_text(_element), do: ""

  defp fields_text(fields) when is_list(fields) do
    fields
    |> Enum.map(&element_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp fields_text(_fields), do: ""

  defp attachments_text(attachments) when is_list(attachments) do
    attachments
    |> Enum.map(&attachment_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp attachments_text(_attachments), do: ""

  defp attachment_text(attachment) when is_map(attachment) do
    title =
      case {attachment["title"], attachment["title_link"]} do
        {title, link} when is_binary(title) and is_binary(link) -> "#{title} (#{link})"
        {title, _link} when is_binary(title) -> title
        _ -> ""
      end

    fields =
      attachment["fields"]
      |> List.wrap()
      |> Enum.map(&attachment_field/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    body = attachment["text"] || attachment["fallback"] || ""

    [title, body, fields]
    |> Enum.map(&unescape_mrkdwn/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp attachment_text(_attachment), do: ""

  defp attachment_field(%{"title" => title, "value" => value})
       when is_binary(title) and is_binary(value) and title != "" and value != "" do
    "#{title}: #{value}"
  end

  defp attachment_field(%{"value" => value}) when is_binary(value), do: value
  defp attachment_field(_field), do: ""

  defp unescape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace(~r/<(https?:\/\/[^|>]+)\|([^>]+)>/, "\\2 (\\1)")
    |> String.replace(~r/<(https?:\/\/[^>]+)>/, "\\1")
    |> String.replace("*", "")
  end

  defp unescape_mrkdwn(_text), do: ""

  defp squeeze(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
