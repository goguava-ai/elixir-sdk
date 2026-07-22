defmodule Guava.Call.Runtime do
  @moduledoc false
  # One process per live call. Owns the GuavaSocket connection and a per-call
  # ETS table (collected fields + variables), threads the agent module's per-call
  # state, and dispatches events to the module's callbacks — serialized inline so
  # state updates can't race. Field/variable reads go straight to ETS (see
  # Guava.Call), so a handler can read fields without deadlocking this process.

  use GenServer
  require Logger

  alias Guava.{Call, Events, Commands, Socket, HTTP, SuggestedAction}

  alias Guava.Commands.{
    SetPersona,
    RegisteredHooks,
    SetVariable,
    AnswerQuestion,
    ActionSuggestion,
    ActionCandidate,
    ChoiceResult,
    ExpertError
  }

  defmodule State do
    @moduledoc false
    defstruct [:module, :call, :user_state, :socket, :emit_fn, :hooks, :ets, :terminal_ref]
  end

  # ---- API used by Guava.Call ----

  def emit(server, command), do: GenServer.cast(server, {:emit, command})

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  # ---- GenServer ----

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :agent)
    call_id = Keyword.fetch!(opts, :call_id)
    call_info = Keyword.fetch!(opts, :call_info)
    initial_variables = opts[:initial_variables] || %{}
    route = opts[:route] || "v2/connect-call"

    Logger.metadata(call_id: call_id)
    ets = :ets.new(:guava_call, [:set, :public, read_concurrency: true, write_concurrency: true])
    call = %Call{id: call_id, call_info: call_info, server: self(), table: ets}

    {:ok, user_state} = module.init(call_info)
    {socket, emit_fn} = setup_transport(opts, call_id, route)

    maybe_register(call_id)

    state = %State{
      module: module,
      call: call,
      user_state: user_state,
      socket: socket,
      emit_fn: emit_fn,
      hooks: module.__guava_hooks__(),
      ets: ets
    }

    {:ok, state, {:continue, {:init_call, initial_variables}}}
  end

  defp setup_transport(opts, call_id, route) do
    cond do
      emit = opts[:emit] ->
        {opts[:socket], emit}

      opts[:start_socket] == false ->
        {nil, fn _ -> :ok end}

      true ->
        client = opts[:client] || Guava.Client.new!()
        url = HTTP.ws_url(client, "#{route}/#{call_id}")

        {:ok, socket} =
          Socket.start_link(
            url: url,
            name: "call-#{call_id}",
            headers: HTTP.headers(client),
            owner: self(),
            max_age_ms: 18_000_000
          )

        {socket, fn payload -> Socket.send_payload(socket, payload) end}
    end
  end

  defp maybe_register(call_id) do
    case Process.whereis(Guava.CallRegistry) do
      nil -> :ok
      _ -> Registry.register(Guava.CallRegistry, call_id, nil)
    end
  end

  @impl true
  def handle_continue({:init_call, initial_variables}, %State{module: module, call: call} = state) do
    persona = module.agent_info(call.call_info)

    do_emit(state, %SetPersona{
      agent_name: persona[:name],
      organization_name: persona[:organization],
      agent_purpose: persona[:purpose],
      voice: persona[:voice]
    })

    do_emit(state, %RegisteredHooks{
      has_on_question: state.hooks.has_on_question,
      has_on_intent: false,
      has_on_action_requested: state.hooks.has_on_action_requested,
      has_on_escalate: state.hooks.has_on_escalate,
      accept_dtmf_for_numbers: state.hooks.accept_dtmf
    })

    Enum.each(initial_variables, fn {k, v} ->
      :ets.insert(state.ets, {{:var, k}, v})
      do_emit(state, %SetVariable{key: k, value: v})
    end)

    user_state = safe_noreply(state, fn -> module.handle_start(call, state.user_state) end)
    {:noreply, %{state | user_state: user_state}}
  end

  @impl true
  def handle_cast({:emit, command}, state) do
    do_emit(state, command)
    {:noreply, state}
  end

  @impl true
  def handle_info({:guava_socket, _pid, :ready}, state), do: {:noreply, state}

  def handle_info({:guava_socket, _pid, {:payload, map}}, state) do
    case Events.decode(map) do
      nil -> {:noreply, state}
      event -> process_event(event, state)
    end
  end

  def handle_info({:guava_socket, _pid, {:closed, reason, _desc}}, state) do
    Logger.debug("Call socket closed: #{reason}")
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{terminal_ref: ref} = state) do
    {:stop, :normal, state}
  end

  # Arbitrary external messages → user handle_info/3.
  def handle_info(msg, %State{module: module, call: call} = state) do
    user_state = safe_noreply(state, fn -> module.handle_info(msg, call, state.user_state) end)
    {:noreply, %{state | user_state: user_state}}
  end

  @impl true
  def terminate(reason, %State{module: module, call: call, user_state: us}) do
    _ = safe(fn -> module.terminate(reason, call, us) end)
    :ok
  end

  # ---- event processing (serialized, inline) ----

  defp process_event(%Events.ActionItemCompleted{key: key, payload: payload}, state) do
    :ets.insert(state.ets, {{:field, key}, payload})
    if key && payload, do: Logger.info("Field #{key} updated.")
    {:noreply, state}
  end

  defp process_event(%Events.CallerSpeech{} = e, %State{module: m, call: c} = s) do
    us = safe_noreply(s, fn -> m.handle_caller_speech(c, e, s.user_state) end)
    {:noreply, %{s | user_state: us}}
  end

  defp process_event(%Events.AgentSpeech{} = e, %State{module: m, call: c} = s) do
    us = safe_noreply(s, fn -> m.handle_agent_speech(c, e, s.user_state) end)
    {:noreply, %{s | user_state: us}}
  end

  defp process_event(
         %Events.AgentQuestion{question_id: qid, question: q},
         %State{module: m, call: c} = s
       ) do
    {us, answer} =
      safe_reply(
        s,
        fn -> m.handle_question(c, q, s.user_state) end,
        "An error occurred and the question could not be answered."
      )

    do_emit(s, %AnswerQuestion{question_id: qid, answer: answer})
    {:noreply, %{s | user_state: us}}
  end

  defp process_event(
         %Events.ActionRequest{intent_id: iid, intent_summary: summary},
         %State{module: m, call: c} = s
       ) do
    case safe(fn -> m.handle_action_request(c, summary, s.user_state) end) do
      {:ok, {:reply, suggestion, us}} ->
        do_emit(s, %ActionSuggestion{intent_id: iid, actions: to_candidates(suggestion)})
        {:noreply, %{s | user_state: us}}

      {:error, _e} ->
        do_emit(s, %ExpertError{
          message:
            "The expert encountered an error while processing the on_action_request handler."
        })

        do_emit(s, %ActionSuggestion{intent_id: iid, actions: []})
        {:noreply, s}
    end
  end

  defp process_event(%Events.ExecuteAction{action_key: key}, %State{module: m, call: c} = s) do
    us =
      safe_noreply(s, fn -> m.handle_action(key, c, s.user_state) end, fn ->
        %ExpertError{
          message:
            "The expert encountered an error while processing the on_action('#{key}') handler."
        }
      end)

    {:noreply, %{s | user_state: us}}
  end

  defp process_event(%Events.TaskCompleted{task_id: task_id}, %State{module: m, call: c} = s) do
    {s, errors} = run_validations(s, task_id)

    case errors do
      [] ->
        Logger.info("Task #{task_id} completed.")

        us =
          safe_noreply(s, fn -> m.handle_task_complete(task_id, c, s.user_state) end, fn ->
            %ExpertError{
              message:
                "The expert encountered an error while processing on_task_complete('#{task_id}')."
            }
          end)

        {:noreply, %{s | user_state: us}}

      msgs ->
        do_emit(s, %Commands.RetryTask{reason: Enum.join(msgs, " ")})
        {:noreply, s}
    end
  end

  defp process_event(
         %Events.ChoiceQuery{field_key: fk, query: query, query_id: qid},
         %State{module: m, call: c} = s
       ) do
    case safe(fn -> m.handle_search_query(fk, c, query, s.user_state) end) do
      {:ok, {:reply, {matched, other}, us}} ->
        do_emit(s, %ChoiceResult{
          field_key: fk,
          query_id: qid,
          matched_choices: matched,
          other_choices: other
        })

        {:noreply, %{s | user_state: us}}

      {:error, _e} ->
        do_emit(s, %ExpertError{
          message: "The expert encountered an error while processing on_search_query('#{fk}')."
        })

        {:noreply, s}
    end
  end

  defp process_event(%Events.DTMFPressed{} = e, %State{module: m, call: c} = s) do
    us = safe_noreply(s, fn -> m.handle_dtmf(c, e, s.user_state) end)
    {:noreply, %{s | user_state: us}}
  end

  defp process_event(%Events.Escalate{requested_by: by}, %State{module: m, call: c} = s) do
    if s.hooks.has_on_escalate do
      us =
        safe_noreply(s, fn -> m.handle_escalate(c, s.user_state) end, fn ->
          %ExpertError{message: "The expert encountered an error while processing on_escalate."}
        end)

      {:noreply, %{s | user_state: us}}
    else
      instruction =
        if by == "agent" do
          "No escalation target set. Apologize for not being able to help, ask them to try calling another time, and hang up the call immediately."
        else
          "Let them know there are no respresentatives available to take their call. Ask them if they would prefer to continue or to call another time."
        end

      do_emit(s, %Guava.Commands.SendInstruction{instruction: instruction})
      {:noreply, s}
    end
  end

  defp process_event(%Events.Error{content: content}, s) do
    Logger.error("Received error from Guava server: #{content}")
    {:noreply, s}
  end

  defp process_event(%Events.Warning{content: content}, s) do
    Logger.warning("Received warning from Guava server: #{content}")
    {:noreply, s}
  end

  defp process_event(%Events.OutboundCallConnected{}, s), do: {:noreply, s}

  defp process_event(%Events.BotSessionEnded{} = e, %State{module: m, call: c} = s) do
    Logger.info("Session ended: #{e.termination_reason}")
    us = safe_noreply(s, fn -> m.handle_session_end(c, e, s.user_state) end)
    {:stop, :normal, %{s | user_state: us}}
  end

  defp process_event(%Events.OutboundCallFailed{} = e, %State{module: m, call: c} = s) do
    Logger.error("Outbound call failed: #{e.error_reason}")
    us = safe_noreply(s, fn -> m.handle_outbound_failed(c, e, s.user_state) end)
    {:stop, :normal, %{s | user_state: us}}
  end

  defp process_event(event, s) do
    Logger.warning("Received unexpected event: #{inspect(event)}")
    {:noreply, s}
  end

  # ---- callback interpreters ----

  # Run each of the task's field validators (via handle_validate/4), threading the
  # user state. Returns the updated state and any error messages, in order. Fields
  # without a validator hit the injected default and pass.
  defp run_validations(%State{module: m, call: c} = s, task_id) do
    field_keys =
      case :ets.lookup(s.ets, {:task_fields, task_id}) do
        [{_, keys}] -> keys
        [] -> []
      end

    {user_state, errors} =
      Enum.reduce(field_keys, {s.user_state, []}, fn key, {us, errs} ->
        {us, result} =
          safe_reply(
            %{s | user_state: us},
            fn ->
              m.handle_validate(key, c, Call.get_field(c, key), us)
            end,
            :ok
          )

        case result do
          {:error, msg} -> {us, [msg | errs]}
          _ok -> {us, errs}
        end
      end)

    {%{s | user_state: user_state}, Enum.reverse(errors)}
  end

  # Run a void callback, returning the new user state; on error, log, optionally
  # emit a command, and keep the previous state.
  defp safe_noreply(state, fun, on_error \\ nil) do
    case safe(fun) do
      {:ok, {:noreply, us}} ->
        us

      {:ok, other} ->
        Logger.error("callback returned #{inspect(other)}; expected {:noreply, state}")
        state.user_state

      {:error, _e} ->
        if on_error, do: do_emit(state, on_error.())
        state.user_state
    end
  end

  # Run a reply callback, returning {new_user_state, reply_value}; on error, keep
  # state and use the fallback reply.
  defp safe_reply(state, fun, fallback) do
    case safe(fun) do
      {:ok, {:reply, value, us}} ->
        {us, value}

      {:ok, other} ->
        Logger.error("callback returned #{inspect(other)}; expected {:reply, value, state}")
        {state.user_state, fallback}

      {:error, _e} ->
        {state.user_state, fallback}
    end
  end

  defp safe(fun) do
    {:ok, fun.()}
  rescue
    e ->
      Logger.error("Guava agent callback raised: #{Exception.message(e)}")
      {:error, e}
  end

  defp to_candidates(nil), do: []

  defp to_candidates(%SuggestedAction{key: k, description: d}),
    do: [%ActionCandidate{key: k, description: d || ""}]

  defp to_candidates(list) when is_list(list),
    do:
      Enum.map(list, fn %SuggestedAction{key: k, description: d} ->
        %ActionCandidate{key: k, description: d || ""}
      end)

  defp do_emit(%State{emit_fn: emit_fn}, command) do
    :telemetry.execute([:guava, :command, :sent], %{}, %{command: command.command_type})
    emit_fn.(Commands.to_map(command))
  end
end
