defmodule Guava.Testing do
  @moduledoc """
  Drive an agent module against Guava's `v1/test-agent` endpoint — no phone needed.

      Guava.Testing.session(MyAgent, fn session ->
        Guava.Testing.Session.say(session, "Hi, what are your hours?")
        Guava.Testing.Session.wait_for_turn(session)
        Guava.Testing.Session.evaluate(session, ["The agent gave hours."], [])
      end)

  Or let an LLM roleplay the caller with `roleplay/3`.
  """
  require Logger

  alias Guava.Testing.Session

  @roleplay_max_turns 20

  @doc """
  Run `agent_module` against a live test session and pass the session to `fun`.
  The session is stopped when `fun` returns.

  ## Options
    * `:variables` — initial call variables
    * `:client` — a `Guava.Client` (defaults to `Guava.Client.new!/0`)
  """
  @spec session(module(), (pid() -> result), keyword()) :: result when result: var
  def session(agent_module, fun, opts \\ []) do
    {:ok, s} = Session.start_link([agent: agent_module] ++ opts)

    try do
      fun.(s)
    after
      Session.stop(s)
    end
  end

  @doc """
  Run an automated roleplay where an LLM plays the caller. Returns the
  (still-running) session so you can `Guava.Testing.Session.evaluate/3` then
  `Guava.Testing.Session.stop/1`.
  """
  @spec roleplay(module(), String.t(), keyword()) :: pid()
  def roleplay(agent_module, roleplay_prompt, opts \\ []) do
    client = opts[:client] || Guava.Client.new!()
    {:ok, s} = Session.start_link([agent: agent_module, client: client] ++ opts)
    roleplay_loop(client, s, roleplay_prompt, 0)
    s
  end

  defp roleplay_loop(_client, _session, _prompt, turn) when turn >= @roleplay_max_turns, do: :ok

  defp roleplay_loop(client, session, prompt, turn) do
    Session.wait_for_turn(session)
    transcript = Session.get_transcript(session)

    schema = %{
      "type" => "object",
      "required" => ["action"],
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ["speak", "hangup"]},
        "utterance" => %{"type" => "string"}
      }
    }

    full_prompt = """
    #{prompt}

    You are roleplaying as a caller on a phone call. Decide what to do next based on the conversation so far.

    Conversation:
    #{if transcript == "", do: "(The agent has not spoken yet)", else: transcript}

    Choose "speak" and provide your next utterance, or choose "hangup" if the conversation has naturally concluded.
    """

    case client |> Guava.LLM.generate!(full_prompt, schema) |> Jason.decode!() do
      %{"action" => "speak", "utterance" => utterance} when is_binary(utterance) ->
        Session.say(session, utterance)
        roleplay_loop(client, session, prompt, turn + 1)

      _ ->
        :ok
    end
  end
end
