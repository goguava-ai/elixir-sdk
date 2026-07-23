defmodule Guava.Testing.MockCall do
  @moduledoc """
  An in-memory `Guava.Call` for unit-testing agent callbacks without a server.

  `Guava.Testing.session/3` drives a whole agent against the live test endpoint;
  `MockCall` is the complement for fast, offline, deterministic tests: call a
  single handler directly and assert on the commands it emits — no network, no
  LLM, no supervision.

  A mock records every command your handler emits, in order, and holds an
  ETS-backed store for field and variable reads, so `Guava.Call` actions and
  reads behave exactly as they do on a live call.

      test "assigns the intake task on call start" do
        mock = Guava.Testing.MockCall.new()

        {:noreply, _state} =
          MyAgent.handle_call_started(mock.call, MyAgent.initial_state())

        assert [%Guava.Commands.SetTask{task_id: "intake"}] =
                 Guava.Testing.MockCall.commands(mock)
      end

  Pre-seed collected fields and variables that a handler reads back:

      mock = Guava.Testing.MockCall.new(fields: %{"email" => "a@b.com"})
      Guava.Testing.MockCall.put_variable(mock, "tier", "gold")

  Assert on the exact wire shape with `command_maps/1`:

      Guava.Call.send_dtmf(mock.call, "123")
      assert [%{"command_type" => "send-agent-dtmf", "digits" => ["1", "2", "3"]}] =
               Guava.Testing.MockCall.command_maps(mock)

  ## Scope

  A mock exercises a handler *in isolation*. It does not run the call runtime, so
  runtime orchestration — for example, field validators firing automatically when
  a task completes — is out of scope; cover that with a live `session/3`. You can
  still unit-test a validator directly by calling `c:Guava.Agent.handle_validate/4`
  yourself.

  > #### Command capture is per-process {: .info}
  >
  > Commands are captured from the process that calls the handler. If a handler
  > offloads work to a spawned `Task`, emits from that task are not visible to
  > `commands/1` unless you await it first.
  """

  use GenServer

  alias Guava.{Call, Commands}

  @enforce_keys [:call, :pid, :table]
  defstruct [:call, :pid, :table]

  @type t :: %__MODULE__{call: Call.t(), pid: pid(), table: :ets.tid()}

  @doc """
  Build a mock call.

  The recorder process is linked to the calling (test) process, so it — and its
  ETS store — are cleaned up automatically when the test ends.

  ## Options
    * `:id` — the call/session id (default: a generated `"mock-…"` id).
    * `:call_info` — a `Guava.CallInfo` (default: a PSTN call). Pass a
      `Guava.CallInfo.WebRTC{}` to exercise WebRTC-only guards.
    * `:fields` — map of `field_key => value` to pre-seed as collected fields.
    * `:variables` — map of `key => value` to pre-seed as call variables.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    id = opts[:id] || "mock-" <> Guava.Internal.random_hex(6)

    call_info =
      opts[:call_info] ||
        %Guava.CallInfo.PSTN{from_number: "+15555555555", to_number: "+15555555555"}

    table = :ets.new(:guava_mock_call, [:set, :public])
    {:ok, pid} = GenServer.start_link(__MODULE__, [])

    mock = %__MODULE__{
      call: %Call{id: id, call_info: call_info, server: pid, table: table},
      pid: pid,
      table: table
    }

    Enum.each(opts[:fields] || %{}, fn {k, v} -> set_field(mock, k, v) end)
    Enum.each(opts[:variables] || %{}, fn {k, v} -> put_variable(mock, k, v) end)
    mock
  end

  @doc """
  The `Guava.Call` handle to pass to your handlers. Equivalent to `mock.call`.
  """
  @spec call(t()) :: Call.t()
  def call(%__MODULE__{call: call}), do: call

  @doc """
  Pre-seed a collected field value, readable via `Guava.Call.get_field/3`.

  Emits no command (unlike a field being collected during a live call).
  """
  @spec set_field(t(), String.t(), term()) :: t()
  def set_field(%__MODULE__{table: table} = mock, key, value) do
    :ets.insert(table, {{:field, key}, value})
    mock
  end

  @doc """
  Pre-seed a call variable, readable via `Guava.Call.get_variable/3`.

  Emits no command, unlike `Guava.Call.set_variable/3`.
  """
  @spec put_variable(t(), String.t(), term()) :: t()
  def put_variable(%__MODULE__{table: table} = mock, key, value) do
    :ets.insert(table, {{:var, key}, value})
    mock
  end

  @doc "Every command emitted so far, as structs, in the order emitted."
  @spec commands(t()) :: [struct()]
  def commands(%__MODULE__{pid: pid}), do: GenServer.call(pid, :commands)

  @doc """
  Every command emitted so far as wire maps (via `Guava.Commands.to_map/1`), in
  order — for asserting on the exact serialized shape.
  """
  @spec command_maps(t()) :: [map()]
  def command_maps(mock), do: Enum.map(commands(mock), &Commands.to_map/1)

  @doc "Discard all recorded commands (e.g. between simulated turns)."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{pid: pid} = mock) do
    GenServer.call(pid, :clear)
    mock
  end

  @doc """
  Stop the recorder process. Optional — it is linked to the test process and
  stops with it.
  """
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid}), do: GenServer.stop(pid)

  # ---- GenServer: a command sink standing in for Guava.Call.Runtime ----

  @impl true
  def init(_), do: {:ok, []}

  @impl true
  def handle_cast({:emit, command}, cmds), do: {:noreply, [command | cmds]}
  def handle_cast(_other, cmds), do: {:noreply, cmds}

  @impl true
  def handle_call(:commands, _from, cmds), do: {:reply, Enum.reverse(cmds), cmds}
  def handle_call(:clear, _from, _cmds), do: {:reply, :ok, []}

  @impl true
  def handle_info(_msg, cmds), do: {:noreply, cmds}
end
