defmodule AndnativeAi.Slack.MessageTextTest do
  use ExUnit.Case, async: true

  alias AndnativeAi.Slack.MessageText

  describe "app_message?/1" do
    test "detects bot_message subtype" do
      assert MessageText.app_message?(%{"subtype" => "bot_message"})
    end

    test "detects bot_id author" do
      assert MessageText.app_message?(%{"bot_id" => "B123"})
    end

    test "detects bot_profile author" do
      assert MessageText.app_message?(%{"bot_profile" => %{"name" => "Linear"}})
    end

    test "human plain-text messages are not app messages" do
      refute MessageText.app_message?(%{"user" => "U1", "text" => "hello"})
    end
  end

  describe "self_authored?/2" do
    test "matches the direct bot user" do
      assert MessageText.self_authored?(%{"user" => "UBOT"}, "UBOT")
    end

    test "matches the bot profile user id" do
      assert MessageText.self_authored?(%{"bot_profile" => %{"user_id" => "UBOT"}}, "UBOT")
    end

    test "does not match other authors or blank bot ids" do
      refute MessageText.self_authored?(%{"user" => "U1"}, "UBOT")
      refute MessageText.self_authored?(%{"user" => "U1"}, nil)
      refute MessageText.self_authored?(%{"user" => "U1"}, "")
    end
  end

  describe "extract/1" do
    test "flattens section and header blocks" do
      message = %{
        "text" => "",
        "blocks" => [
          %{"type" => "header", "text" => %{"type" => "plain_text", "text" => "Release shipped"}},
          %{
            "type" => "section",
            "text" => %{"type" => "mrkdwn", "text" => "*MiniMax* support added"},
            "fields" => [
              %{"type" => "mrkdwn", "text" => "Status: Done"},
              %{"type" => "mrkdwn", "text" => "Owner: Marcel"}
            ]
          }
        ]
      }

      text = MessageText.extract(message)
      assert text =~ "Release shipped"
      assert text =~ "MiniMax support added"
      assert text =~ "Status: Done"
      assert text =~ "Owner: Marcel"
    end

    test "flattens rich_text blocks with links" do
      message = %{
        "blocks" => [
          %{
            "type" => "rich_text",
            "elements" => [
              %{
                "type" => "rich_text_section",
                "elements" => [
                  %{"type" => "text", "text" => "New issue "},
                  %{
                    "type" => "link",
                    "url" => "https://linear.app/team/issue/AAI-42",
                    "text" => "AAI-42"
                  }
                ]
              }
            ]
          }
        ]
      }

      text = MessageText.extract(message)
      assert text =~ "New issue"
      assert text =~ "AAI-42 (https://linear.app/team/issue/AAI-42)"
    end

    test "flattens attachments with title, body, and fields" do
      message = %{
        "text" => "",
        "attachments" => [
          %{
            "title" => "AAI-42 Add MiniMax provider",
            "title_link" => "https://linear.app/native-ai/issue/AAI-42",
            "text" => "Adds MiniMax as an LLM provider option.",
            "fields" => [
              %{"title" => "Status", "value" => "In Progress"},
              %{"title" => "Assignee", "value" => "Marcel"}
            ]
          }
        ]
      }

      text = MessageText.extract(message)
      assert text =~ "AAI-42 Add MiniMax provider (https://linear.app/native-ai/issue/AAI-42)"
      assert text =~ "Adds MiniMax as an LLM provider option."
      assert text =~ "Status: In Progress"
      assert text =~ "Assignee: Marcel"
    end

    test "unescapes slack mrkdwn links in plain text" do
      message = %{"text" => "See <https://linear.app/native-ai/issue/AAI-7|AAI-7> for details"}

      assert MessageText.extract(message) =~
               "AAI-7 (https://linear.app/native-ai/issue/AAI-7)"
    end
  end

  describe "normalize/1" do
    test "tags app messages and merges attachment text" do
      message = %{
        "type" => "message",
        "subtype" => "bot_message",
        "bot_id" => "BLINEAR",
        "bot_profile" => %{"name" => "Linear"},
        "ts" => "1710000000.000200",
        "text" => "",
        "attachments" => [
          %{
            "title" => "AAI-42 Add MiniMax provider",
            "title_link" => "https://linear.app/native-ai/issue/AAI-42",
            "text" => "Status changed to Done"
          }
        ]
      }

      normalized = MessageText.normalize(message)

      assert normalized["app_message"] == true
      assert normalized["text"] =~ "Linear update:"
      assert normalized["text"] =~ "AAI-42 Add MiniMax provider"
      assert normalized["text"] =~ "Status changed to Done"
      assert normalized["app_link"] == "https://linear.app/native-ai/issue/AAI-42"
    end

    test "leaves human messages untouched" do
      message = %{"type" => "message", "user" => "U1", "text" => "we decided to ship"}
      assert MessageText.normalize(message) == message
    end
  end

  describe "linear_message?/1" do
    test "detects linear by bot profile name" do
      assert MessageText.linear_message?(%{
               "subtype" => "bot_message",
               "bot_profile" => %{"name" => "Linear"},
               "text" => "something"
             })
    end

    test "detects linear by url" do
      assert MessageText.linear_message?(%{
               "bot_id" => "B1",
               "text" => "New issue https://linear.app/native-ai/issue/AAI-9"
             })
    end

    test "human message with linear url is not an app message" do
      refute MessageText.linear_message?(%{
               "user" => "U1",
               "text" => "look at https://linear.app/native-ai/issue/AAI-9"
             })
    end
  end
end
