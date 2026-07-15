defmodule Guava.WireTest do
  @moduledoc """
  Verifies the Elixir wire structs serialize/deserialize identically to the
  Python SDK, using ground-truth fixtures generated from pydantic's model_dump
  (see scripts/gen_fixtures.py).
  """
  use ExUnit.Case, async: true

  alias Guava.Commands
  alias Guava.Commands.{ActionSuggestion, ActionCandidate}
  alias Guava.{Events, Field, SerializableField, Say, Todo, CallInfo, IncomingCallAction}

  @fixtures "test/fixtures/wire.json" |> File.read!() |> Jason.decode!()

  defp dump(category, key), do: @fixtures[category][key]["dump"]

  describe "commands encode identically to pydantic model_dump" do
    cmds = %{
      "accept_inbound" => %Commands.AcceptInbound{},
      "action_suggestion_empty" => %ActionSuggestion{intent_id: "i1"},
      "action_suggestion_legacy" =>
        ActionSuggestion.new(intent_id: "i1", action_key: "sales", action_description: "d"),
      "action_suggestion_multi" => %ActionSuggestion{
        intent_id: "i1",
        actions: [%ActionCandidate{key: "a", description: "d"}, %ActionCandidate{key: "b"}]
      },
      "answer_question" => %Commands.AnswerQuestion{question_id: "q1", answer: "42"},
      "choice_result" => %Commands.ChoiceResult{
        field_key: "slot",
        query_id: "q9",
        matched_choices: ["a"],
        other_choices: ["b", "c"]
      },
      "expert_error" => %Commands.ExpertError{message: "boom"},
      "listen_inbound" => %Commands.ListenInbound{agent_number: "+14155550100"},
      "read_script" => %Commands.ReadScript{script: "Hello"},
      "reconnect_outbound" => %Commands.ReconnectOutboundSession{
        session_id: "sess_1",
        highest_seen_sequence: 7
      },
      "registered_hooks" => %Commands.RegisteredHooks{
        has_on_question: true,
        has_on_intent: false,
        has_on_action_requested: true,
        has_on_escalate: false
      },
      "reject_inbound" => %Commands.RejectInbound{},
      "retry_task" => %Commands.RetryTask{reason: "bad"},
      "send_caller_text" => %Commands.SendCallerText{text: "hi"},
      "send_instruction" => %Commands.SendInstruction{instruction: "Do the thing"},
      "set_agent_dtmf" => %Commands.SetAgentDTMF{enabled: true},
      "set_language_mode" => %Commands.SetLanguageMode{primary: "english", secondary: ["spanish"]},
      "set_language_mode_default" => %Commands.SetLanguageMode{},
      "set_persona" => %Commands.SetPersona{
        agent_name: "Nova",
        organization_name: "Acme",
        agent_purpose: "help",
        voice: "alloy"
      },
      "set_persona_empty" => %Commands.SetPersona{},
      "set_task" => %Commands.SetTask{
        task_id: "abc123",
        objective: "Collect info",
        completion_criteria: "done",
        action_items: [
          %SerializableField{key: "name", description: "their name"},
          %Say{statement: "Hi there", key: "g1"},
          %Todo{description: "Verify identity", key: "t1"}
        ]
      },
      "set_task_min" => %Commands.SetTask{task_id: "t", objective: "o", action_items: []},
      "set_variable" => %Commands.SetVariable{key: "k", value: %{"nested" => [1, 2, "x"]}},
      "set_variable_scalar" => %Commands.SetVariable{key: "k", value: 5},
      "start_outbound" => %Commands.StartOutboundCall{
        from_number: "+14155550100",
        to_number: "+14155550111"
      },
      "start_outbound_no_from" => %Commands.StartOutboundCall{
        from_number: nil,
        to_number: "+14155550111"
      },
      "transfer_call" => %Commands.Transfer{
        transfer_message: "transferring",
        to_number: "+14155550999",
        soft_transfer: true
      }
    }

    for {key, struct} <- cmds do
      @tag key: key
      test "#{key}" do
        assert Commands.to_map(unquote(Macro.escape(struct))) == dump("commands", unquote(key))
      end
    end
  end

  describe "types encode identically" do
    types = %{
      "accept" => %IncomingCallAction.Accept{},
      "decline" => %IncomingCallAction.Decline{},
      "serializable_field" => %SerializableField{key: "k", is_search_field: true},
      "say" => %Say{statement: "hello", key: "s1"},
      "todo" => %Todo{description: "do it", key: "t1"},
      "pstn" => %CallInfo.PSTN{
        from_number: "+14155550100",
        to_number: "+14155550111",
        caller_id: "Bob"
      },
      "webrtc" => %CallInfo.WebRTC{webrtc_code: "w1"},
      "sip" => %CallInfo.Sip{from_aor: "sip:a@b", sip_code: "s1", sip_headers: %{"X" => "Y"}}
    }

    for {key, struct} <- types do
      @tag key: key
      test "#{key}" do
        actual = unquote(Macro.escape(struct)) |> Jason.encode!() |> Jason.decode!()
        assert actual == dump("types", unquote(key))
      end
    end
  end

  describe "events decode from pydantic dumps" do
    for key <- Map.keys(@fixtures["events"]) do
      @tag key: key
      test "#{key}" do
        dump = dump("events", unquote(key))
        event = Events.decode(dump)
        assert event != nil
        assert event.event_type == dump["event_type"]
        assert event.sequence == dump["sequence"]
      end
    end

    test "specific field extraction" do
      assert %Events.CallerSpeech{utterance: "hello", utterance_id: "u1"} =
               Events.decode(dump("events", "caller_speech"))

      assert %Events.AgentSpeech{interrupted: true} =
               Events.decode(dump("events", "agent_speech"))

      assert %Events.AgentSpeech{interrupted: false} =
               Events.decode(dump("events", "agent_speech_min"))

      assert %Events.BotSessionEnded{termination_reason: "user-hangup", dnc: false} =
               Events.decode(dump("events", "bot_session_ended"))

      assert %Events.DTMFPressed{digit: "5"} = Events.decode(dump("events", "dtmf"))
      assert %Events.Escalate{requested_by: "agent"} = Events.decode(dump("events", "escalate"))

      assert %Events.Escalate{requested_by: "human"} =
               Events.decode(dump("events", "escalate_default"))

      assert %Events.ActionItemCompleted{key: "name", payload: %{"value" => "Bob"}} =
               Events.decode(dump("events", "action_item_done"))

      assert %Events.CallerSpeech{sequence: 3} = Events.decode(dump("events", "with_sequence"))
    end

    test "bot-session-ended decodes dnc: true" do
      assert %Events.BotSessionEnded{dnc: true} =
               Events.decode(%{
                 "event_type" => "bot-session-ended",
                 "termination_reason" => "user-hangup",
                 "dnc" => true
               })
    end

    test "unknown event type decodes to nil" do
      assert Events.decode(%{"event_type" => "brand-new-event", "foo" => 1}) == nil
    end
  end

  describe "CallInfo.from_map round-trips" do
    test "pstn / webrtc / sip" do
      pstn = CallInfo.from_map(dump("types", "pstn"))

      assert %CallInfo.PSTN{
               from_number: "+14155550100",
               to_number: "+14155550111",
               caller_id: "Bob"
             } = pstn

      webrtc = CallInfo.from_map(dump("types", "webrtc"))
      assert %CallInfo.WebRTC{webrtc_code: "w1"} = webrtc

      sip = CallInfo.from_map(dump("types", "sip"))
      assert %CallInfo.Sip{from_aor: "sip:a@b", sip_code: "s1", sip_headers: %{"X" => "Y"}} = sip
    end
  end

  describe "Field validation" do
    test "datetime not implemented" do
      assert_raise ArgumentError, ~r/not yet implemented/, fn ->
        Field.new(key: "k", field_type: "datetime")
      end
    end

    test "choices require multiple_choice or calendar_slot" do
      assert_raise ArgumentError, ~r/does not support choices/, fn ->
        Field.new(key: "k", field_type: "text", choices: ["a"])
      end
    end

    test "calendar_slot choices must be ISO-8601" do
      assert_raise ArgumentError, ~r/ISO-8601/, fn ->
        Field.new(key: "k", field_type: "calendar_slot", choices: ["tomorrow"])
      end

      assert %Field{} =
               Field.new(key: "k", field_type: "calendar_slot", choices: ["2026-07-02T10:00"])
    end

    test "valid multiple_choice field" do
      assert %Field{choices: ["a", "b"]} =
               Field.new(key: "k", field_type: "multiple_choice", choices: ["a", "b"])
    end
  end
end
