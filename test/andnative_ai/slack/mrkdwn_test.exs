defmodule AndnativeAi.Slack.MrkdwnTest do
  use ExUnit.Case, async: true

  alias AndnativeAi.Slack.Mrkdwn
  alias AndnativeAi.Slack.SocketModeConnection

  describe "from_markdown/1" do
    test "converts bold, links, headings, and bullets" do
      markdown = """
      ## How we work

      - We're remote and mostly **async**: post first.
      - **Radiate your work**: answer the daily check-in.

      Sources: [How We Work](https://example.com/admin/memory#memory-source-1)
      """

      mrkdwn = Mrkdwn.from_markdown(markdown)

      assert mrkdwn =~ "*How we work*"
      assert mrkdwn =~ "• We're remote and mostly *async*: post first."
      assert mrkdwn =~ "• *Radiate your work*: answer the daily check-in."
      assert mrkdwn =~ "<https://example.com/admin/memory#memory-source-1|How We Work>"
      refute mrkdwn =~ "**"
      refute mrkdwn =~ "]("
    end

    test "leaves fenced code blocks untouched" do
      markdown = "```\n**not bold** [not](https://a.link)\n```"
      assert Mrkdwn.from_markdown(markdown) == markdown
    end

    test "passes plain text through" do
      assert Mrkdwn.from_markdown("just a sentence.") == "just a sentence."
    end
  end

  describe "retry?/1" do
    test "detects Slack redeliveries at envelope and payload level" do
      assert SocketModeConnection.retry?(%{"retry_attempt" => 1})
      assert SocketModeConnection.retry?(%{"payload" => %{"retry_attempt" => 2}})
      refute SocketModeConnection.retry?(%{"retry_attempt" => 0})
      refute SocketModeConnection.retry?(%{"payload" => %{"event" => %{}}})
    end
  end
end
