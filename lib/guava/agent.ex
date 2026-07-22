defmodule Guava.Agent do
  @moduledoc """
  Behaviour for a voice agent, in the spirit of `GenServer`/`Phoenix.LiveView`:
  `use Guava.Agent`, give it a persona, and implement only the callbacks you need.

  Each call gets its own process; your callbacks thread a per-call **state**
  value (like a LiveView socket's assigns) and return standard tuples. Use the
  `Guava.Call` handle passed to each callback to drive the conversation
  (`set_task`, `transfer`, `get_field`, …).

  ## Example

      defmodule MyAgent do
        use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Answer questions."

        @impl true
        def init(_call_info), do: {:ok, %{}}

        @impl true
        def handle_question(_call, question, state), do: {:reply, MyKB.answer(question), state}

        @impl true
        def handle_action("sales", call, state) do
          Guava.Call.transfer(call, "+14155550100")
          {:noreply, state}
        end
      end

  Attach it to a channel with `Guava.Channel` (see its docs) or `Guava.run/1`.

  ## Callbacks

  All callbacks are optional; a persona-only agent is valid. Callbacks that
  produce a reply to the Dialog System return `{:reply, value, state}`; the rest
  return `{:noreply, state}`.

    * `init(call_info)` → `{:ok, state}` — build per-call state (default `%{}`)
    * `agent_info(call_info)` → keyword persona (defaults to the `use` options)
    * `handle_call_received(call_info)` → `:accept` | `:decline` (default `:accept`)
    * `handle_start(call, state)`
    * `handle_caller_speech(call, event, state)` / `handle_agent_speech(call, event, state)`
    * `handle_question(call, question, state)` → `{:reply, answer, state}`
    * `handle_action_request(call, request, state)` → `{:reply, suggestion, state}`
      where suggestion is a `Guava.SuggestedAction`, a list of them, or `nil`
    * `handle_action(action_key, call, state)` — one callback; pattern-match the key
    * `handle_task_complete(task_id, call, state)` — one callback; pattern-match the id
      (a `reach_person/3` task completes as `handle_task_complete("reach_person", …)`)
    * `handle_validate(field_key, call, value, state)` → `{:reply, :ok | {:error, reason}, state}`
      — validates a collected field on task completion; any `{:error, reason}` retries
      the task instead of completing it. Pattern-match the key; include a catch-all
      `handle_validate(_, _, _, state)` returning `{:reply, :ok, state}`.
    * `handle_search_query(field_key, call, query, state)` → `{:reply, {matched, other}, state}`
    * `handle_dtmf(call, event, state)` / `handle_escalate(call, state)`
    * `handle_outbound_failed(call, event, state)` / `handle_session_end(call, event, state)`
    * `handle_info(msg, call, state)` — external mid-call messages (e.g. results of a spawned Task)
    * `terminate(reason, call, state)`
  """
  alias Guava.CallInfo

  @type state :: term()
  @type call :: Guava.Call.t()

  @callback init(CallInfo.t()) :: {:ok, state()}
  @callback agent_info(CallInfo.t()) :: keyword()
  @callback handle_call_received(CallInfo.t()) :: :accept | :decline
  @callback handle_start(call(), state()) :: {:noreply, state()}
  @callback handle_caller_speech(call(), Guava.Events.CallerSpeech.t(), state()) ::
              {:noreply, state()}
  @callback handle_agent_speech(call(), Guava.Events.AgentSpeech.t(), state()) ::
              {:noreply, state()}
  @callback handle_question(call(), String.t(), state()) :: {:reply, String.t(), state()}
  @callback handle_action_request(call(), String.t(), state()) ::
              {:reply, Guava.SuggestedAction.t() | [Guava.SuggestedAction.t()] | nil, state()}
  @callback handle_action(String.t(), call(), state()) :: {:noreply, state()}
  @callback handle_task_complete(String.t(), call(), state()) :: {:noreply, state()}
  @callback handle_validate(String.t(), call(), term(), state()) ::
              {:reply, :ok | {:error, String.t()}, state()}
  @callback handle_search_query(String.t(), call(), String.t(), state()) ::
              {:reply, {[String.t()], [String.t()]}, state()}
  @callback handle_dtmf(call(), Guava.Events.DTMFPressed.t(), state()) :: {:noreply, state()}
  @callback handle_escalate(call(), state()) :: {:noreply, state()}
  @callback handle_outbound_failed(call(), Guava.Events.OutboundCallFailed.t(), state()) ::
              {:noreply, state()}
  @callback handle_session_end(call(), Guava.Events.BotSessionEnded.t(), state()) ::
              {:noreply, state()}
  @callback handle_info(term(), call(), state()) :: {:noreply, state()}
  @callback terminate(term(), call(), state()) :: any()

  @optional_callbacks init: 1,
                      agent_info: 1,
                      handle_call_received: 1,
                      handle_start: 2,
                      handle_caller_speech: 3,
                      handle_agent_speech: 3,
                      handle_question: 3,
                      handle_action_request: 3,
                      handle_action: 3,
                      handle_task_complete: 3,
                      handle_validate: 4,
                      handle_search_query: 4,
                      handle_dtmf: 3,
                      handle_escalate: 2,
                      handle_outbound_failed: 3,
                      handle_session_end: 3,
                      handle_info: 3,
                      terminate: 3

  # The full set of callbacks we inject no-op defaults for.
  @injectable [
    init: 1,
    agent_info: 1,
    handle_call_received: 1,
    handle_start: 2,
    handle_caller_speech: 3,
    handle_agent_speech: 3,
    handle_question: 3,
    handle_action_request: 3,
    handle_action: 3,
    handle_task_complete: 3,
    handle_validate: 4,
    handle_search_query: 4,
    handle_dtmf: 3,
    handle_escalate: 2,
    handle_outbound_failed: 3,
    handle_session_end: 3,
    handle_info: 3,
    terminate: 3
  ]

  @doc false
  def injectable, do: @injectable

  defmacro __using__(opts) do
    persona =
      opts
      |> Keyword.take([:name, :organization, :purpose, :voice])

    accept_dtmf = Keyword.get(opts, :accept_dtmf, true)

    quote do
      @behaviour Guava.Agent
      @guava_persona unquote(persona)
      @guava_accept_dtmf unquote(accept_dtmf)
      @before_compile Guava.Agent
    end
  end

  defmacro __before_compile__(env) do
    mod = env.module

    accept_dtmf = Module.get_attribute(mod, :guava_accept_dtmf)
    accept_dtmf = if is_nil(accept_dtmf), do: true, else: accept_dtmf

    hooks =
      Macro.escape(%{
        has_on_question: Module.defines?(mod, {:handle_question, 3}),
        has_on_action_requested: Module.defines?(mod, {:handle_action_request, 3}),
        has_on_escalate: Module.defines?(mod, {:handle_escalate, 2}),
        accept_dtmf: accept_dtmf
      })

    persona = Module.get_attribute(mod, :guava_persona) || []

    defaults =
      for {name, arity} <- @injectable, not Module.defines?(mod, {name, arity}) do
        Guava.Agent.__default__(name, arity, persona)
      end

    quote do
      @doc false
      def __guava_hooks__, do: unquote(hooks)
      unquote_splicing(defaults)
    end
  end

  @doc false
  # Build the AST for a default implementation of an un-implemented callback.
  def __default__(:init, 1, _), do: quote(do: def(init(_call_info), do: {:ok, %{}}))

  def __default__(:agent_info, 1, persona),
    do: quote(do: def(agent_info(_call_info), do: unquote(persona)))

  def __default__(:handle_call_received, 1, _),
    do: quote(do: def(handle_call_received(_call_info), do: :accept))

  def __default__(:handle_start, 2, _),
    do: quote(do: def(handle_start(_call, state), do: {:noreply, state}))

  def __default__(:handle_caller_speech, 3, _),
    do: quote(do: def(handle_caller_speech(_call, _e, state), do: {:noreply, state}))

  def __default__(:handle_agent_speech, 3, _),
    do: quote(do: def(handle_agent_speech(_call, _e, state), do: {:noreply, state}))

  def __default__(:handle_question, 3, _),
    do:
      quote(
        do:
          def(handle_question(_call, _q, state),
            do: {:reply, "I don't have an answer to that question.", state}
          )
      )

  def __default__(:handle_action_request, 3, _),
    do: quote(do: def(handle_action_request(_call, _r, state), do: {:reply, nil, state}))

  def __default__(:handle_action, 3, _),
    do: quote(do: def(handle_action(_key, _call, state), do: {:noreply, state}))

  def __default__(:handle_task_complete, 3, _),
    do: quote(do: def(handle_task_complete(_task_id, _call, state), do: {:noreply, state}))

  def __default__(:handle_validate, 4, _),
    do: quote(do: def(handle_validate(_fk, _call, _value, state), do: {:reply, :ok, state}))

  def __default__(:handle_search_query, 4, _),
    do: quote(do: def(handle_search_query(_fk, _call, _q, state), do: {:reply, {[], []}, state}))

  def __default__(:handle_dtmf, 3, _),
    do: quote(do: def(handle_dtmf(_call, _e, state), do: {:noreply, state}))

  def __default__(:handle_escalate, 2, _),
    do: quote(do: def(handle_escalate(_call, state), do: {:noreply, state}))

  def __default__(:handle_outbound_failed, 3, _),
    do: quote(do: def(handle_outbound_failed(_call, _e, state), do: {:noreply, state}))

  def __default__(:handle_session_end, 3, _),
    do: quote(do: def(handle_session_end(_call, _e, state), do: {:noreply, state}))

  def __default__(:handle_info, 3, _),
    do: quote(do: def(handle_info(_msg, _call, state), do: {:noreply, state}))

  def __default__(:terminate, 3, _),
    do: quote(do: def(terminate(_reason, _call, _state), do: :ok))
end
