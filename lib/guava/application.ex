defmodule Guava.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Supervises transient work like per-event handler tasks.
      {Task.Supervisor, name: Guava.TaskSupervisor},
      # Registry of live calls by call id (for observability / external control).
      {Registry, keys: :unique, name: Guava.CallRegistry},
      # Supervises dynamically started sockets, calls, and channel listeners.
      {DynamicSupervisor, name: Guava.CallSupervisor, strategy: :one_for_one},
      # Optional, opt-in usage reporting (off unless configured).
      Guava.Usage
    ]

    opts = [strategy: :one_for_one, name: Guava.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
