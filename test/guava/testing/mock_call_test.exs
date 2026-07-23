defmodule Guava.Testing.MockCallTest do
  use ExUnit.Case, async: true

  alias Guava.{Call, Field}
  alias Guava.Commands.{SetTask, RetryTask}
  alias Guava.Testing.MockCall

  test "new/1 builds a usable Call handle" do
    mock = MockCall.new(id: "abc")
    assert %Call{id: "abc"} = mock.call
    assert %Guava.CallInfo.PSTN{} = mock.call.call_info
    assert MockCall.call(mock) == mock.call
    assert MockCall.commands(mock) == []
  end

  test "records emitted commands as structs, in order" do
    mock = MockCall.new()

    Call.set_task(mock.call, "one", objective: "first")
    Call.retry_task(mock.call, "bad")

    assert [%SetTask{task_id: "one"}, %RetryTask{reason: "bad"}] = MockCall.commands(mock)
  end

  test "command_maps/1 returns wire maps" do
    mock = MockCall.new()
    Call.set_task(mock.call, "t", checklist: [Field.new(key: "name", description: "their name")])

    assert [%{"command_type" => "set-task", "task_id" => "t"}] = MockCall.command_maps(mock)
  end

  test "set_field/3 and the :fields option prime reads without emitting" do
    mock = MockCall.new(fields: %{"email" => "a@b.com"})
    MockCall.set_field(mock, "name", "Ada")

    assert Call.get_field(mock.call, "email") == "a@b.com"
    assert Call.get_field(mock.call, "name") == "Ada"
    assert Call.has_field?(mock.call, "name")
    refute Call.has_field?(mock.call, "missing")
    assert MockCall.commands(mock) == []
  end

  test "put_variable/3 primes get_variable without emitting a command" do
    mock = MockCall.new(variables: %{"tier" => "gold"})
    MockCall.put_variable(mock, "lang", "en")

    assert Call.get_variable(mock.call, "tier") == "gold"
    assert Call.get_variable(mock.call, "lang") == "en"
    assert MockCall.commands(mock) == []
  end

  test "clear/1 discards recorded commands" do
    mock = MockCall.new()
    Call.retry_task(mock.call, "a")
    assert [%RetryTask{}] = MockCall.commands(mock)

    MockCall.clear(mock)
    assert MockCall.commands(mock) == []

    Call.retry_task(mock.call, "b")
    assert [%RetryTask{reason: "b"}] = MockCall.commands(mock)
  end

  test "a handler called in isolation records what it emits" do
    # Stand-in for a user callback: reads a primed field, emits a command.
    handler = fn call ->
      if Call.get_field(call, "verified") == true do
        Call.send_instruction(call, "welcome back")
      else
        Call.retry_task(call, "verify identity")
      end
    end

    mock = MockCall.new(fields: %{"verified" => true})
    handler.(mock.call)

    assert [%{"command_type" => "send-instruction", "instruction" => "welcome back"}] =
             MockCall.command_maps(mock)
  end
end
