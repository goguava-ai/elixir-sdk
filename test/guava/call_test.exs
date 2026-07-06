defmodule Guava.CallTest do
  use ExUnit.Case, async: true

  alias Guava.{Call, Field, Say}
  alias Guava.Test.CommandRecorder

  defp new_call do
    {:ok, rec} = CommandRecorder.start_link(self())
    table = :ets.new(:guava_call_test, [:set, :public])

    %Call{
      id: "c1",
      call_info: %Guava.CallInfo.PSTN{to_number: "+14155550111"},
      server: rec,
      table: table
    }
  end

  test "set_task converts a mixed checklist into action items" do
    call = new_call()

    Call.set_task(call, "collect",
      objective: "Collect info",
      checklist: [
        Field.new(key: "name", description: "their name"),
        "verify identity",
        Say.new("One moment", "s1")
      ]
    )

    assert_receive {:command, %{"command_type" => "set-task"} = cmd}, 1000
    assert cmd["task_id"] == "collect"
    [field, todo, say] = cmd["action_items"]

    assert field["item_type"] == "field" and field["key"] == "name" and
             field["is_search_field"] == false

    assert todo["item_type"] == "todo" and todo["description"] == "verify identity"
    assert say == %{"item_type" => "say", "statement" => "One moment", "key" => "s1"}
  end

  test "searchable field maps to is_search_field" do
    call = new_call()

    Call.set_task(call, "t",
      checklist: [Field.new(key: "slot", field_type: "multiple_choice", searchable: true)]
    )

    assert_receive {:command, %{"command_type" => "set-task", "action_items" => [item]}}, 1000
    assert item["is_search_field"] == true
  end

  test "reach_person builds a reach_person task with a contact_availability field" do
    call = new_call()
    Call.reach_person(call, "John Smith")

    assert_receive {:command, %{"command_type" => "set-task"} = cmd}, 1000
    assert cmd["task_id"] == "reach_person"
    assert cmd["objective"] =~ "reach John Smith"
    field = Enum.find(cmd["action_items"], &(&1["item_type"] == "field"))
    assert field["key"] == "contact_availability" and field["field_type"] == "multiple_choice"
    assert "available" in field["choices"] and "voicemail" in field["choices"]
  end

  test "set_variable writes ETS and emits; get_variable/get_field read ETS" do
    call = new_call()
    Call.set_variable(call, "customer", %{"name" => "Ada"})

    assert_receive {:command,
                    %{
                      "command_type" => "set-variable",
                      "key" => "customer",
                      "value" => %{"name" => "Ada"}
                    }},
                   1000

    assert Call.get_variable(call, "customer") == %{"name" => "Ada"}
    assert Call.get_field(call, "missing", :default) == :default

    :ets.insert(call.table, {{:field, "email"}, "a@b.com"})
    assert Call.get_field(call, "email") == "a@b.com"
    assert Call.has_field?(call, "email")
    refute Call.has_field?(call, "nope")
  end

  test "set_variable rejects non-JSON values" do
    call = new_call()
    assert_raise ArgumentError, fn -> Call.set_variable(call, "bad", {:a, :tuple}) end
  end

  test "hangup and transfer emit the right commands" do
    call = new_call()

    Call.hangup(call, "Thanks for calling")

    assert_receive {:command, %{"command_type" => "send-instruction", "instruction" => inst}},
                   1000

    assert inst =~ "Thanks for calling"

    Call.transfer(call, "+14155559999")

    assert_receive {:command,
                    %{
                      "command_type" => "transfer-call",
                      "to_number" => "+14155559999",
                      "soft_transfer" => true
                    }},
                   1000
  end
end
