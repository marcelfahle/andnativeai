defmodule AndnativeAi.Runtime.AnthropicClientTest do
  use ExUnit.Case, async: false

  alias AndnativeAi.Runtime.AnthropicClient

  setup do
    Application.put_env(:andnative_ai, :anthropic_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:andnative_ai, :anthropic_req_options) end)
    :ok
  end

  defp request do
    %{
      api_key: "sk-ant-test",
      model: "claude-opus-4-8",
      instructions: "You are Bran.",
      input: "Draft a launch email.",
      max_output_tokens: 900
    }
  end

  test "maps the request onto the Messages API and returns the text block" do
    Req.Test.stub(__MODULE__, fn conn ->
      # Headers carry the Anthropic auth contract, not a bearer token.
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["sk-ant-test"]
      assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]

      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      assert body["model"] == "claude-opus-4-8"
      assert body["system"] == "You are Bran."
      assert body["max_tokens"] == 900
      assert [%{"role" => "user", "content" => "Draft a launch email."}] = body["messages"]

      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "thinking", "thinking" => "ignore me"},
          %{"type" => "text", "text" => "  Subject: we shipped.  "}
        ]
      })
    end)

    assert {:ok, "Subject: we shipped."} = AnthropicClient.response(request())
  end

  test "a non-200 response becomes an error tuple, never a raise" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"type" => "rate_limit_error"}})
    end)

    assert {:error, {:unexpected_anthropic_response, 429, _body}} =
             AnthropicClient.response(request())
  end

  test "an empty text block is an error, not an empty answer" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "   "}]})
    end)

    assert {:error, :missing_output_text} = AnthropicClient.response(request())
  end

  test "transport failures surface as error tuples" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, _reason} = AnthropicClient.response(request())
  end
end
