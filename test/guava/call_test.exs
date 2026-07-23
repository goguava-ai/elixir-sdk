defmodule Guava.CallTest do
  use ExUnit.Case, async: true

  alias Guava.{Call, Field, Say}
  alias Guava.Testing.MockCall

  defp new_call(call_info \\ %Guava.CallInfo.PSTN{to_number: "+14155550111"}) do
    MockCall.new(call_info: call_info)
  end

  test "set_task converts a mixed checklist into action items" do
    mock = new_call()

    Call.set_task(mock.call, "collect",
      objective: "Collect info",
      checklist: [
        Field.new(key: "name", description: "their name"),
        "verify identity",
        Say.new("One moment", "s1")
      ]
    )

    assert [%{"command_type" => "set-task"} = cmd] = MockCall.command_maps(mock)
    assert cmd["task_id"] == "collect"
    [field, todo, say] = cmd["action_items"]

    assert field["item_type"] == "field" and field["key"] == "name" and
             field["is_search_field"] == false

    assert todo["item_type"] == "todo" and todo["description"] == "verify identity"
    assert say == %{"item_type" => "say", "statement" => "One moment", "key" => "s1"}
  end

  test "searchable field maps to is_search_field" do
    mock = new_call()

    Call.set_task(mock.call, "t",
      checklist: [Field.new(key: "slot", field_type: "multiple_choice", searchable: true)]
    )

    assert [%{"command_type" => "set-task", "action_items" => [item]}] =
             MockCall.command_maps(mock)

    assert item["is_search_field"] == true
  end

  test "reach_person builds a reach_person task with a contact_availability field" do
    mock = new_call()
    Call.reach_person(mock.call, "John Smith")

    assert [%{"command_type" => "set-task"} = cmd] = MockCall.command_maps(mock)
    assert cmd["task_id"] == "reach_person"
    assert cmd["objective"] =~ "reach John Smith"
    field = Enum.find(cmd["action_items"], &(&1["item_type"] == "field"))
    assert field["key"] == "contact_availability" and field["field_type"] == "multiple_choice"
    assert "available" in field["choices"] and "voicemail" in field["choices"]
  end

  test "set_variable writes ETS and emits; get_variable/get_field read ETS" do
    mock = new_call()
    call = mock.call
    Call.set_variable(call, "customer", %{"name" => "Ada"})

    assert [
             %{
               "command_type" => "set-variable",
               "key" => "customer",
               "value" => %{"name" => "Ada"}
             }
           ] = MockCall.command_maps(mock)

    assert Call.get_variable(call, "customer") == %{"name" => "Ada"}
    assert Call.get_field(call, "missing", :default) == :default

    MockCall.set_field(mock, "email", "a@b.com")
    assert Call.get_field(call, "email") == "a@b.com"
    assert Call.has_field?(call, "email")
    refute Call.has_field?(call, "nope")
  end

  test "set_variable rejects non-JSON values" do
    mock = new_call()
    assert_raise ArgumentError, fn -> Call.set_variable(mock.call, "bad", {:a, :tuple}) end
  end

  test "set_task records the task's field keys in ETS (fields only)" do
    mock = new_call()

    Call.set_task(mock.call, "collect",
      checklist: [
        Field.new(key: "name", description: "their name"),
        Field.new(key: "email", description: "their email"),
        "verify identity",
        Say.new("One moment", "s1")
      ]
    )

    assert [{{:task_fields, "collect"}, ["name", "email"]}] =
             :ets.lookup(mock.table, {:task_fields, "collect"})
  end

  test "a sensitive field carries sensitive: true onto the wire" do
    mock = new_call()

    Call.set_task(mock.call, "t",
      checklist: [Field.new(key: "cvv", field_type: "cvv", sensitive: true)]
    )

    assert [%{"command_type" => "set-task", "action_items" => [item]}] =
             MockCall.command_maps(mock)

    assert item["sensitive"] == true and item["field_type"] == "cvv"
  end

  test "send_dtmf validates digits and emits send-agent-dtmf in order" do
    mock = new_call()

    Call.send_dtmf(mock.call, "123")
    Call.send_dtmf(mock.call, ["4", "#"])

    assert [
             %{"command_type" => "send-agent-dtmf", "digits" => ["1", "2", "3"]},
             %{"command_type" => "send-agent-dtmf", "digits" => ["4", "#"]}
           ] = MockCall.command_maps(mock)

    assert_raise ArgumentError, fn -> Call.send_dtmf(mock.call, "12x") end
  end

  test "DTMF is rejected on WebRTC calls" do
    mock = new_call(%Guava.CallInfo.WebRTC{webrtc_code: "w1"})

    assert_raise ArgumentError, ~r/WebRTC/, fn -> Call.send_dtmf(mock.call, "1") end
    assert_raise ArgumentError, ~r/WebRTC/, fn -> Call.set_agent_dtmf(mock.call, true) end
  end

  test "hangup and transfer emit the right commands in order" do
    mock = new_call()

    Call.hangup(mock.call, "Thanks for calling")
    Call.transfer(mock.call, "+14155559999")

    assert [
             %{"command_type" => "send-instruction", "instruction" => inst},
             %{
               "command_type" => "transfer-call",
               "to_number" => "+14155559999",
               "soft_transfer" => true
             }
           ] = MockCall.command_maps(mock)

    assert inst =~ "Thanks for calling"
  end
end
