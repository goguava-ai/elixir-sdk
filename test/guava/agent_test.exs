defmodule Guava.AgentTest do
  use ExUnit.Case, async: false

  alias Guava.Call.Runtime

  @inbox {__MODULE__, :inbox}

  # ── Test agent modules ──────────────────────────────────────────────────────

  defmodule StateAgent do
    use Guava.Agent, name: "Nova", organization: "Acme", purpose: "help"

    @impl true
    def init(_ci), do: {:ok, %{count: 0}}

    @impl true
    def handle_start(call, state) do
      Guava.Call.send_instruction(call, "started")
      {:noreply, %{state | count: state.count + 1}}
    end

    @impl true
    def handle_caller_speech(call, event, state) do
      Guava.Call.send_instruction(call, "count=#{state.count} heard=#{event.utterance}")
      {:noreply, %{state | count: state.count + 1}}
    end

    @impl true
    def handle_question(_call, q, state), do: {:reply, "answer to #{q}", state}

    @impl true
    def handle_action_request(_call, _req, state) do
      {:reply,
       [Guava.SuggestedAction.new("sales", "sales dept"), Guava.SuggestedAction.new("support")],
       state}
    end

    @impl true
    def handle_action("sales", call, state) do
      Guava.Call.transfer(call, "+14155559999")
      {:noreply, state}
    end

    @impl true
    def handle_search_query("slot", _call, _q, state), do: {:reply, {["a"], ["b", "c"]}, state}

    @impl true
    def handle_task_complete("reach_person", call, state) do
      Guava.Call.send_instruction(
        call,
        "reached: #{Guava.Call.get_field(call, "contact_availability")}"
      )

      {:noreply, state}
    end

    @impl true
    def handle_session_end(_call, event, state) do
      send(:persistent_term.get({Guava.AgentTest, :inbox}), {:ended, event.termination_reason})
      {:noreply, state}
    end
  end

  defmodule PersonaOnly do
    use Guava.Agent, name: "Min", organization: "Acme", purpose: "greet"
  end

  defmodule HooksAgent do
    use Guava.Agent, name: "H"
    @impl true
    def handle_question(_c, _q, s), do: {:reply, "x", s}
    @impl true
    def handle_action_request(_c, _r, s), do: {:reply, nil, s}
  end

  defmodule DtmfOffAgent do
    use Guava.Agent, name: "D", accept_dtmf: false
  end

  defmodule MultiValidateAgent do
    use Guava.Agent, name: "MV"

    @impl true
    def handle_start(call, state) do
      Guava.Call.set_task(call, "collect2",
        checklist: [
          Guava.Field.new(key: "a", description: "a"),
          Guava.Field.new(key: "b", description: "b")
        ]
      )

      {:noreply, state}
    end

    @impl true
    def handle_validate("a", _call, _value, state), do: {:reply, {:error, "A invalid."}, state}
    def handle_validate("b", _call, _value, state), do: {:reply, {:error, "B invalid."}, state}
    def handle_validate(_key, _call, _value, state), do: {:reply, :ok, state}
  end

  defmodule ThreadValidateAgent do
    use Guava.Agent, name: "TV"

    @impl true
    def init(_ci), do: {:ok, %{validated: []}}

    @impl true
    def handle_start(call, state) do
      Guava.Call.set_task(call, "collect3",
        checklist: [
          Guava.Field.new(key: "x", description: "x"),
          Guava.Field.new(key: "y", description: "y")
        ]
      )

      {:noreply, state}
    end

    # Each validator appends its key, threading the accumulated state forward.
    @impl true
    def handle_validate(key, _call, _value, state),
      do: {:reply, :ok, %{state | validated: state.validated ++ [key]}}

    @impl true
    def handle_task_complete("collect3", call, state) do
      Guava.Call.send_instruction(call, "validated: #{Enum.join(state.validated, ",")}")
      {:noreply, state}
    end
  end

  defmodule ValidatingAgent do
    use Guava.Agent, name: "V"

    @impl true
    def handle_start(call, state) do
      Guava.Call.set_task(call, "collect",
        checklist: [Guava.Field.new(key: "email", description: "their email")]
      )

      {:noreply, state}
    end

    @impl true
    def handle_validate("email", _call, value, state) do
      if is_binary(value) and String.contains?(value, "@"),
        do: {:reply, :ok, state},
        else: {:reply, {:error, "Please provide a valid email."}, state}
    end

    def handle_validate(_key, _call, _value, state), do: {:reply, :ok, state}

    @impl true
    def handle_task_complete("collect", call, state) do
      Guava.Call.send_instruction(call, "task validated")
      {:noreply, state}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  setup do
    :persistent_term.put(@inbox, self())
    :ok
  end

  defp start_runtime(module, opts \\ []) do
    test = self()

    {:ok, pid} =
      Runtime.start_link(
        [
          agent: module,
          call_id: "c1",
          call_info: %Guava.CallInfo.PSTN{from_number: nil, to_number: "+14155550111"},
          emit: fn map -> send(test, {:command, map}) end
        ] ++ opts
      )

    pid
  end

  defp feed(pid, event_map), do: send(pid, {:guava_socket, self(), {:payload, event_map}})

  defp assert_command(type) do
    assert_receive {:command, %{"command_type" => ^type} = cmd}, 1000
    cmd
  end

  # ── tests ───────────────────────────────────────────────────────────────────

  test "init emits persona, registered hooks (from callbacks), and initial variables" do
    start_runtime(StateAgent, initial_variables: %{"lang" => "en"})

    persona = assert_command("set-persona")
    assert persona["agent_name"] == "Nova" and persona["organization_name"] == "Acme"

    hooks = assert_command("registered-hooks")
    assert hooks["has_on_question"] == true and hooks["has_on_action_requested"] == true

    var = assert_command("set-variable")
    assert var["key"] == "lang" and var["value"] == "en"
  end

  test "threads per-call state across callbacks" do
    pid = start_runtime(StateAgent)
    # handle_start incremented count 0 -> 1.
    feed(pid, %{"event_type" => "caller-speech", "utterance" => "hello"})

    assert_receive {:command,
                    %{
                      "command_type" => "send-instruction",
                      "instruction" => "count=1 heard=hello"
                    }},
                   1000
  end

  test "handle_question reply" do
    pid = start_runtime(StateAgent)
    feed(pid, %{"event_type" => "agent-question", "question_id" => "q1", "question" => "hours?"})
    cmd = assert_command("answer-question")
    assert cmd["question_id"] == "q1" and cmd["answer"] == "answer to hours?"
  end

  test "handle_action_request returns suggestions" do
    pid = start_runtime(StateAgent)
    feed(pid, %{"event_type" => "action-request", "intent_id" => "i1", "intent_summary" => "buy"})
    cmd = assert_command("action-suggestion")

    assert cmd["actions"] == [
             %{"key" => "sales", "description" => "sales dept"},
             %{"key" => "support", "description" => ""}
           ]
  end

  test "handle_action (pattern-matched key) executes" do
    pid = start_runtime(StateAgent)
    feed(pid, %{"event_type" => "execute-action", "action_key" => "sales"})
    assert assert_command("transfer-call")["to_number"] == "+14155559999"
  end

  test "handle_search_query returns matched/other" do
    pid = start_runtime(StateAgent)

    feed(pid, %{
      "event_type" => "choice-query",
      "field_key" => "slot",
      "query" => "am",
      "query_id" => "q9"
    })

    cmd = assert_command("choice-query-result")
    assert cmd["matched_choices"] == ["a"] and cmd["other_choices"] == ["b", "c"]
  end

  test "field updates are readable in a task-complete handler" do
    pid = start_runtime(StateAgent)

    feed(pid, %{
      "event_type" => "action-item-done",
      "key" => "contact_availability",
      "payload" => "available"
    })

    feed(pid, %{"event_type" => "task-done", "task_id" => "reach_person"})

    assert_receive {:command,
                    %{"command_type" => "send-instruction", "instruction" => "reached: available"}},
                   1000
  end

  test "bot-session-ended runs handle_session_end then stops" do
    pid = start_runtime(StateAgent)
    ref = Process.monitor(pid)
    feed(pid, %{"event_type" => "bot-session-ended", "termination_reason" => "user-hangup"})
    assert_receive {:ended, "user-hangup"}, 1000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "persona-only agent: default question answer and default escalate instruction" do
    pid = start_runtime(PersonaOnly)
    feed(pid, %{"event_type" => "agent-question", "question_id" => "q1", "question" => "?"})
    assert assert_command("answer-question")["answer"] =~ "don't have an answer"

    feed(pid, %{"event_type" => "escalate", "requested_by" => "human"})
    assert assert_command("send-instruction")["instruction"] =~ "no respresentatives"
  end

  test "__guava_hooks__ reflects exactly the user-defined hooks" do
    assert HooksAgent.__guava_hooks__() == %{
             has_on_question: true,
             has_on_action_requested: true,
             has_on_escalate: false,
             accept_dtmf: true
           }

    assert PersonaOnly.__guava_hooks__() == %{
             has_on_question: false,
             has_on_action_requested: false,
             has_on_escalate: false,
             accept_dtmf: true
           }
  end

  test "accept_dtmf option flows into __guava_hooks__ and the registered-hooks command" do
    assert DtmfOffAgent.__guava_hooks__().accept_dtmf == false

    start_runtime(DtmfOffAgent)
    assert assert_command("registered-hooks")["accept_dtmf_for_numbers"] == false
  end

  test "handle_validate failure retries the task instead of completing it" do
    pid = start_runtime(ValidatingAgent)

    # Collect the field, then complete the task with an invalid value.
    feed(pid, %{"event_type" => "action-item-done", "key" => "email", "payload" => "not-an-email"})

    feed(pid, %{"event_type" => "task-done", "task_id" => "collect"})

    assert assert_command("retry-task")["reason"] =~ "valid email"

    refute_receive {:command,
                    %{"command_type" => "send-instruction", "instruction" => "validated"}}
  end

  test "handle_validate success lets the task complete" do
    pid = start_runtime(ValidatingAgent)

    feed(pid, %{"event_type" => "action-item-done", "key" => "email", "payload" => "a@b.com"})
    feed(pid, %{"event_type" => "task-done", "task_id" => "collect"})

    refute_receive {:command, %{"command_type" => "retry-task"}}
    assert assert_command("send-instruction")["instruction"] =~ "validated"
  end

  test "handle_validate joins multiple field errors in field order" do
    pid = start_runtime(MultiValidateAgent)
    feed(pid, %{"event_type" => "task-done", "task_id" => "collect2"})

    assert assert_command("retry-task")["reason"] == "A invalid. B invalid."
  end

  test "handle_validate threads state into handle_task_complete" do
    pid = start_runtime(ThreadValidateAgent)
    feed(pid, %{"event_type" => "task-done", "task_id" => "collect3"})

    assert assert_command("send-instruction")["instruction"] == "validated: x,y"
  end
end
