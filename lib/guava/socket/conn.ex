defmodule Guava.Socket.Conn do
  @moduledoc false
  # A thin WebSockex relay. It does no protocol work: it forwards raw text
  # frames and lifecycle events to its parent process, which owns all
  # reconnection and reliable-protocol logic (Guava.Socket).
  use WebSockex

  @doc "Connect to `url`, relaying events to `parent`. Returns `{:ok, pid}` or `{:error, reason}`."
  def start(url, parent, headers) do
    WebSockex.start(url, __MODULE__, %{parent: parent},
      extra_headers: headers,
      handle_initial_conn_failure: true
    )
  end

  @doc "Send a text frame on an established connection."
  def send_text(pid, text), do: WebSockex.send_frame(pid, {:text, text})

  @impl true
  def handle_connect(_conn, %{parent: parent} = state) do
    send(parent, {:conn_up, self()})
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, text}, %{parent: parent} = state) do
    send(parent, {:ws_frame, text})
    {:ok, state}
  end

  def handle_frame(_other, state), do: {:ok, state}

  @impl true
  def handle_disconnect(%{reason: reason}, %{parent: parent} = state) do
    send(parent, {:ws_down, reason})
    # Do not auto-reconnect; the parent decides when and how.
    {:ok, state}
  end
end
