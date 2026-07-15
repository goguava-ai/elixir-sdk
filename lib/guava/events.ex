defmodule Guava.Events.OutboundSessionStarted do
  @moduledoc "Deprecated. Retained for compatibility with older servers."
  defstruct sequence: nil, event_type: "session-started", session_id: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          session_id: String.t()
        }
end

defmodule Guava.Events.InboundCall do
  @moduledoc "An inbound call has arrived."
  defstruct sequence: nil, event_type: "inbound-call", caller_number: nil, agent_number: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          caller_number: String.t() | nil,
          agent_number: String.t() | nil
        }
end

defmodule Guava.Events.SocketHealth do
  @moduledoc "A socket health heartbeat."
  defstruct sequence: nil, event_type: "socket-health"
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t()}
end

defmodule Guava.Events.CallerSpeech do
  @moduledoc "The caller said something. Utterances sharing an id supersede earlier ones."
  defstruct sequence: nil, event_type: "caller-speech", utterance: nil, utterance_id: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          utterance: String.t(),
          utterance_id: String.t() | nil
        }
end

defmodule Guava.Events.AgentSpeech do
  @moduledoc "The agent said something."
  defstruct sequence: nil, event_type: "agent-speech", utterance: nil, interrupted: false

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          utterance: String.t(),
          interrupted: boolean()
        }
end

defmodule Guava.Events.Error do
  @moduledoc "An error occurred during the call."
  defstruct sequence: nil, event_type: "error", content: nil
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t(), content: String.t()}
end

defmodule Guava.Events.Warning do
  @moduledoc "A warning occurred during the call."
  defstruct sequence: nil, event_type: "warning", content: nil
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t(), content: String.t()}
end

defmodule Guava.Events.AgentQuestion do
  @moduledoc "The caller asked a question relayed to the developer's system. Expects an answer."
  defstruct sequence: nil, event_type: "agent-question", question_id: nil, question: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          question_id: String.t(),
          question: String.t()
        }
end

defmodule Guava.Events.Intent do
  @moduledoc "The caller declared an intent (legacy)."
  defstruct sequence: nil, event_type: "intent", intent_id: nil, intent_summary: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          intent_id: String.t(),
          intent_summary: String.t()
        }
end

defmodule Guava.Events.ActionRequest do
  @moduledoc "The caller requested an action. Expects an action suggestion."
  defstruct sequence: nil, event_type: "action-request", intent_id: nil, intent_summary: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          intent_id: String.t(),
          intent_summary: String.t()
        }
end

defmodule Guava.Events.ActionItemCompleted do
  @moduledoc "A field/action item was collected."
  defstruct sequence: nil, event_type: "action-item-done", key: nil, payload: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          key: String.t(),
          payload: term()
        }
end

defmodule Guava.Events.TaskCompleted do
  @moduledoc "A task finished."
  defstruct sequence: nil, event_type: "task-done", task_id: nil
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t(), task_id: String.t()}
end

defmodule Guava.Events.ExecuteAction do
  @moduledoc "The agent wants the developer to execute an action."
  defstruct sequence: nil, event_type: "execute-action", action_key: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          action_key: String.t()
        }
end

defmodule Guava.Events.OutboundCallConnected do
  @moduledoc "An outbound call connected."
  defstruct sequence: nil, event_type: "outbound-call-connected"
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t()}
end

defmodule Guava.Events.OutboundCallFailed do
  @moduledoc "An outbound call failed to connect."
  defstruct sequence: nil, event_type: "outbound-call-failed", error_code: nil, error_reason: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          error_code: integer(),
          error_reason: String.t()
        }
end

defmodule Guava.Events.BotSessionEnded do
  @moduledoc "The bot session ended."
  defstruct sequence: nil, event_type: "bot-session-ended", termination_reason: nil, dnc: false

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          termination_reason: String.t(),
          dnc: boolean()
        }
end

defmodule Guava.Events.ChoiceQuery do
  @moduledoc "A searchable-field query needs matching choices."
  defstruct sequence: nil, event_type: "choice-query", field_key: nil, query: nil, query_id: nil

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          field_key: String.t(),
          query: String.t(),
          query_id: String.t()
        }
end

defmodule Guava.Events.Escalate do
  @moduledoc "An escalation was requested by a human or the agent."
  defstruct sequence: nil, event_type: "escalate", requested_by: "human"

  @type t :: %__MODULE__{
          sequence: integer() | nil,
          event_type: String.t(),
          requested_by: String.t()
        }
end

defmodule Guava.Events.DTMFPressed do
  @moduledoc "A DTMF keypad digit was pressed."
  defstruct sequence: nil, event_type: "dtmf", digit: nil
  @type t :: %__MODULE__{sequence: integer() | nil, event_type: String.t(), digit: String.t()}
end

defmodule Guava.Events do
  @moduledoc """
  Server-to-client events received over a call's WebSocket connection.

  Each event is a struct discriminated on the wire by `event_type`. Use
  `decode/1` to turn a decoded JSON map into the matching struct.
  """
  require Logger

  alias Guava.Events

  @typedoc "Any event that can be received from the Guava server."
  @type t ::
          Events.InboundCall.t()
          | Events.SocketHealth.t()
          | Events.CallerSpeech.t()
          | Events.AgentSpeech.t()
          | Events.Error.t()
          | Events.Warning.t()
          | Events.AgentQuestion.t()
          | Events.Intent.t()
          | Events.ActionRequest.t()
          | Events.ActionItemCompleted.t()
          | Events.TaskCompleted.t()
          | Events.ExecuteAction.t()
          | Events.OutboundCallConnected.t()
          | Events.OutboundCallFailed.t()
          | Events.BotSessionEnded.t()
          | Events.ChoiceQuery.t()
          | Events.Escalate.t()
          | Events.DTMFPressed.t()
          | Events.OutboundSessionStarted.t()

  @doc """
  Decode a JSON map into an event struct.

  Returns `nil` (and logs a warning) for unknown event types, matching the
  Python SDK's forward-compatible behavior.
  """
  @spec decode(map()) :: t() | nil
  def decode(%{"event_type" => type} = m) do
    seq = m["sequence"]

    case type do
      "inbound-call" ->
        %Events.InboundCall{
          sequence: seq,
          caller_number: m["caller_number"],
          agent_number: m["agent_number"]
        }

      "socket-health" ->
        %Events.SocketHealth{sequence: seq}

      "caller-speech" ->
        %Events.CallerSpeech{
          sequence: seq,
          utterance: m["utterance"],
          utterance_id: m["utterance_id"]
        }

      "agent-speech" ->
        %Events.AgentSpeech{
          sequence: seq,
          utterance: m["utterance"],
          interrupted: m["interrupted"] || false
        }

      "error" ->
        %Events.Error{sequence: seq, content: m["content"]}

      "warning" ->
        %Events.Warning{sequence: seq, content: m["content"]}

      "agent-question" ->
        %Events.AgentQuestion{
          sequence: seq,
          question_id: m["question_id"],
          question: m["question"]
        }

      "intent" ->
        %Events.Intent{
          sequence: seq,
          intent_id: m["intent_id"],
          intent_summary: m["intent_summary"]
        }

      "action-request" ->
        %Events.ActionRequest{
          sequence: seq,
          intent_id: m["intent_id"],
          intent_summary: m["intent_summary"]
        }

      "action-item-done" ->
        %Events.ActionItemCompleted{sequence: seq, key: m["key"], payload: m["payload"]}

      "task-done" ->
        %Events.TaskCompleted{sequence: seq, task_id: m["task_id"]}

      "execute-action" ->
        %Events.ExecuteAction{sequence: seq, action_key: m["action_key"]}

      "outbound-call-connected" ->
        %Events.OutboundCallConnected{sequence: seq}

      "outbound-call-failed" ->
        %Events.OutboundCallFailed{
          sequence: seq,
          error_code: m["error_code"],
          error_reason: m["error_reason"]
        }

      "bot-session-ended" ->
        %Events.BotSessionEnded{
          sequence: seq,
          termination_reason: m["termination_reason"],
          dnc: m["dnc"] || false
        }

      "choice-query" ->
        %Events.ChoiceQuery{
          sequence: seq,
          field_key: m["field_key"],
          query: m["query"],
          query_id: m["query_id"]
        }

      "escalate" ->
        %Events.Escalate{sequence: seq, requested_by: m["requested_by"] || "human"}

      "dtmf" ->
        %Events.DTMFPressed{sequence: seq, digit: m["digit"]}

      "session-started" ->
        %Events.OutboundSessionStarted{sequence: seq, session_id: m["session_id"]}

      other ->
        Logger.warning(
          "Received an unknown event type #{inspect(other)}. Update to a newer version of this SDK."
        )

        nil
    end
  end

  @doc "Decode an event from a JSON string. Returns `nil` for unknown types."
  @spec decode_json(String.t() | binary()) :: t() | nil
  def decode_json(json), do: json |> Jason.decode!() |> decode()
end
