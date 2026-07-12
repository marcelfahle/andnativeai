defmodule AndnativeAi.Slack.SocketModeListenerTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Slack.SocketModeListener

  defmodule FakeClient do
    def open_socket(_app_token) do
      counter = :counters.get(:persistent_term.get(:socket_counter), 1)
      :counters.add(:persistent_term.get(:socket_counter), 1, 1)
      send(:persistent_term.get(:socket_test_pid), {:socket_opened, counter})
      {:ok, "wss://example.slack.com/socket/#{counter}"}
    end
  end

  defmodule FakeConnection do
    # Stands in for the WebSockex process: a plain linked process the test
    # can terminate to simulate Slack dropping the socket.
    def start_link(url, _state) do
      pid = spawn_link(fn -> loop(url) end)
      send(:persistent_term.get(:socket_test_pid), {:connection_started, url, pid})
      {:ok, pid}
    end

    defp loop(url) do
      receive do
        :die -> exit({:remote, :closed})
        _other -> loop(url)
      end
    end
  end

  test "expired sockets are replaced with fresh single-use URLs" do
    counter = :counters.new(1, [])
    :counters.put(counter, 1, 1)
    :persistent_term.put(:socket_counter, counter)
    :persistent_term.put(:socket_test_pid, self())

    on_exit(fn ->
      :persistent_term.erase(:socket_counter)
      :persistent_term.erase(:socket_test_pid)
    end)

    {:ok, listener} =
      GenServer.start(
        SocketModeListener,
        app_token: "xapp-test-token",
        client: FakeClient,
        connection_module: FakeConnection,
        reconnect_delay_ms: 10
      )

    # First connection uses the first single-use URL.
    assert_receive {:socket_opened, 1}
    assert_receive {:connection_started, "wss://example.slack.com/socket/1", connection}

    # Slack drops the socket (refresh); the listener must request a FRESH
    # URL rather than reusing the expired one.
    send(connection, :die)

    assert_receive {:socket_opened, 2}, 2_000
    assert_receive {:connection_started, "wss://example.slack.com/socket/2", _new_connection}

    # The listener survived the abnormal connection exit.
    assert Process.alive?(listener)
    GenServer.stop(listener)
  end
end
