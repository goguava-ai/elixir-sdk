defmodule Guava.Usage do
  @moduledoc """
  Optional, opt-in usage reporting (uploads batched method-call/exception events
  to `v1/upload-telemetry`).

  Distinct from `:telemetry` instrumentation (which the SDK also emits, for you
  to hook). This is **off** by default — enable with `config :guava, usage_telemetry: true`.
  """
  use GenServer
  require Logger

  alias Guava.HTTP

  @upload_interval_ms 10_000
  @queue_max 100

  defmodule State do
    @moduledoc false
    defstruct client: nil, queue: [], enabled: false
  end

  @doc false
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Set the client used for uploads (no-op when disabled)."
  @spec set_client(Guava.Client.t()) :: :ok
  def set_client(client), do: GenServer.cast(__MODULE__, {:set_client, client})

  @doc "Record a usage event (dropped when disabled or the queue is full)."
  @spec track(String.t(), map()) :: :ok
  def track(event_type, data \\ %{}), do: GenServer.cast(__MODULE__, {:track, event_type, data})

  @doc "Whether usage reporting is enabled via config."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:guava, :usage_telemetry, false) == true

  @impl true
  def init(_) do
    if enabled?(), do: Process.send_after(self(), :upload, @upload_interval_ms)
    {:ok, %State{enabled: enabled?()}}
  end

  @impl true
  def handle_cast({:set_client, client}, state), do: {:noreply, %{state | client: client}}

  def handle_cast({:track, _type, _data}, %State{enabled: false} = state), do: {:noreply, state}

  def handle_cast({:track, _type, _data}, %State{queue: q} = state) when length(q) >= @queue_max,
    do: {:noreply, state}

  def handle_cast({:track, type, data}, state) do
    event = %{timestamp_ms: Guava.Internal.now_ms(), event_type: type, data: data}
    {:noreply, %{state | queue: [event | state.queue]}}
  end

  @impl true
  def handle_info(:upload, %State{client: client, queue: q} = state)
      when client != nil and q != [] do
    payload = Enum.reverse(q)

    Task.Supervisor.start_child(Guava.TaskSupervisor, fn ->
      try do
        HTTP.request!(client, :post, "v1/upload-telemetry", json: %{events: payload})
      rescue
        _ -> :ok
      end
    end)

    Process.send_after(self(), :upload, @upload_interval_ms)
    {:noreply, %{state | queue: []}}
  end

  def handle_info(:upload, state) do
    Process.send_after(self(), :upload, @upload_interval_ms)
    {:noreply, state}
  end
end
