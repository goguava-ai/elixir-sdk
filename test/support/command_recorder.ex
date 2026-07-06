defmodule Guava.Test.CommandRecorder do
  @moduledoc false
  # A stand-in for Guava.Call.Runtime that records emitted commands (as wire maps)
  # to a test process, so Guava.Call actions can be unit-tested without a socket.
  use GenServer

  def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

  @impl true
  def init(test_pid), do: {:ok, test_pid}

  @impl true
  def handle_cast({:emit, command}, test_pid) do
    send(test_pid, {:command, Guava.Commands.to_map(command)})
    {:noreply, test_pid}
  end
end
