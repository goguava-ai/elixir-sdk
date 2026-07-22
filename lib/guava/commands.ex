defmodule Guava.Commands do
  @moduledoc """
  Client-to-server commands sent over a call's WebSocket connection.

  Each command is a struct that serializes to JSON identically to the Python
  SDK's `model_dump`. They are discriminated on the wire by `command_type`.
  """

  alias Guava.Commands

  @typedoc "Any command that can be sent to the Guava server."
  @type t ::
          Commands.StartOutboundCall.t()
          | Commands.ListenInbound.t()
          | Commands.RejectInbound.t()
          | Commands.AcceptInbound.t()
          | Commands.SetTask.t()
          | Commands.ReadScript.t()
          | Commands.AnswerQuestion.t()
          | Commands.ActionSuggestion.t()
          | Commands.SetPersona.t()
          | Commands.SetLanguageMode.t()
          | Commands.RegisteredHooks.t()
          | Commands.SendInstruction.t()
          | Commands.Transfer.t()
          | Commands.ChoiceResult.t()
          | Commands.RetryTask.t()
          | Commands.SetVariable.t()
          | Commands.SendCallerText.t()
          | Commands.ExpertError.t()
          | Commands.SetAgentDTMF.t()
          | Commands.SendAgentDTMF.t()

  @doc "Encode a command struct to a plain JSON-ready map."
  @spec to_map(t()) :: map()
  def to_map(command), do: command |> Jason.encode!() |> Jason.decode!()
end

defmodule Guava.Commands.StartOutboundCall do
  @moduledoc "Start an outbound PSTN call."
  @derive Jason.Encoder
  defstruct command_type: "start-outbound", from_number: nil, to_number: nil

  @type t :: %__MODULE__{
          command_type: String.t(),
          from_number: String.t() | nil,
          to_number: String.t()
        }
end

defmodule Guava.Commands.ListenInbound do
  @moduledoc "Register this connection as an inbound listener."
  @derive Jason.Encoder
  defstruct command_type: "listen-inbound", agent_number: nil, webrtc_code: nil, sip_code: nil

  @type t :: %__MODULE__{
          command_type: String.t(),
          agent_number: String.t() | nil,
          webrtc_code: String.t() | nil,
          sip_code: String.t() | nil
        }
end

defmodule Guava.Commands.RejectInbound do
  @moduledoc "Reject the current inbound call."
  @derive Jason.Encoder
  defstruct command_type: "reject-inbound"
  @type t :: %__MODULE__{command_type: String.t()}
end

defmodule Guava.Commands.AcceptInbound do
  @moduledoc "Accept the current inbound call."
  @derive Jason.Encoder
  defstruct command_type: "accept-inbound"
  @type t :: %__MODULE__{command_type: String.t()}
end

defmodule Guava.Commands.SetTask do
  @moduledoc "Assign a task (objective + checklist of action items) to the agent."
  @derive Jason.Encoder
  defstruct command_type: "set-task",
            task_id: nil,
            objective: "",
            completion_criteria: nil,
            action_items: []

  @type action_item :: Guava.SerializableField.t() | Guava.Say.t() | Guava.Todo.t()
  @type t :: %__MODULE__{
          command_type: String.t(),
          task_id: String.t(),
          objective: String.t(),
          completion_criteria: String.t() | nil,
          action_items: [action_item()]
        }
end

defmodule Guava.Commands.ReadScript do
  @moduledoc "Have the agent read a script verbatim."
  @derive Jason.Encoder
  defstruct command_type: "read-script", script: nil
  @type t :: %__MODULE__{command_type: String.t(), script: String.t()}
end

defmodule Guava.Commands.AnswerQuestion do
  @moduledoc "Answer a question the agent relayed to the developer's system."
  @derive Jason.Encoder
  defstruct command_type: "answer-question", question_id: nil, answer: nil
  @type t :: %__MODULE__{command_type: String.t(), question_id: String.t(), answer: String.t()}
end

defmodule Guava.Commands.ActionCandidate do
  @moduledoc "A candidate action returned in an action suggestion."
  @derive Jason.Encoder
  @enforce_keys [:key]
  defstruct key: nil, description: ""
  @type t :: %__MODULE__{key: String.t(), description: String.t()}
end

defmodule Guava.Commands.ActionSuggestion do
  @moduledoc """
  Suggest zero or more actions in response to an action request.

  Empty `actions` means no match; one means an unambiguous intent; multiple
  means an ambiguous intent to disambiguate with the caller.
  """
  alias Guava.Commands.ActionCandidate

  @derive Jason.Encoder
  defstruct command_type: "action-suggestion",
            intent_id: nil,
            action_key: nil,
            action_description: "",
            actions: []

  @type t :: %__MODULE__{
          command_type: String.t(),
          intent_id: String.t(),
          action_key: String.t() | nil,
          action_description: String.t(),
          actions: [ActionCandidate.t()]
        }

  @doc """
  Build an action suggestion, normalizing the legacy `action_key` field into
  the `actions` list when `actions` is empty (matching the Python model).
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    cmd = struct!(__MODULE__, attrs)

    if cmd.actions == [] and not is_nil(cmd.action_key) do
      %{
        cmd
        | actions: [%ActionCandidate{key: cmd.action_key, description: cmd.action_description}]
      }
    else
      cmd
    end
  end
end

defmodule Guava.Commands.SetPersona do
  @moduledoc "Set the agent's persona (name, organization, purpose, voice)."
  @derive Jason.Encoder
  defstruct command_type: "set-persona",
            agent_name: nil,
            organization_name: nil,
            agent_purpose: nil,
            voice: nil

  @type t :: %__MODULE__{
          command_type: String.t(),
          agent_name: String.t() | nil,
          organization_name: String.t() | nil,
          agent_purpose: String.t() | nil,
          voice: String.t() | nil
        }
end

defmodule Guava.Commands.SetLanguageMode do
  @moduledoc "Set the primary and secondary spoken languages."
  @derive Jason.Encoder
  defstruct command_type: "set-language-mode", primary: "english", secondary: []
  @type t :: %__MODULE__{command_type: String.t(), primary: String.t(), secondary: [String.t()]}
end

defmodule Guava.Commands.RegisteredHooks do
  @moduledoc "Inform the server which developer callbacks are registered."
  @derive Jason.Encoder
  defstruct command_type: "registered-hooks",
            has_on_question: false,
            has_on_intent: false,
            has_on_action_requested: false,
            has_on_escalate: false,
            accept_dtmf_for_numbers: true

  @type t :: %__MODULE__{
          command_type: String.t(),
          has_on_question: boolean(),
          has_on_intent: boolean(),
          has_on_action_requested: boolean(),
          has_on_escalate: boolean(),
          accept_dtmf_for_numbers: boolean()
        }
end

defmodule Guava.Commands.SendInstruction do
  @moduledoc "Send a free-form instruction to steer the agent."
  @derive Jason.Encoder
  defstruct command_type: "send-instruction", instruction: nil
  @type t :: %__MODULE__{command_type: String.t(), instruction: String.t()}
end

defmodule Guava.Commands.Transfer do
  @moduledoc "Transfer the call to another destination."
  @derive Jason.Encoder
  defstruct command_type: "transfer-call",
            transfer_message: nil,
            to_number: nil,
            soft_transfer: false

  @type t :: %__MODULE__{
          command_type: String.t(),
          transfer_message: String.t(),
          to_number: String.t(),
          soft_transfer: boolean()
        }
end

defmodule Guava.Commands.ChoiceResult do
  @moduledoc "Return matched/other choices for a searchable-field query."
  @derive Jason.Encoder
  defstruct command_type: "choice-query-result",
            field_key: nil,
            query_id: nil,
            matched_choices: [],
            other_choices: []

  @type t :: %__MODULE__{
          command_type: String.t(),
          field_key: String.t(),
          query_id: String.t(),
          matched_choices: [String.t()],
          other_choices: [String.t()]
        }
end

defmodule Guava.Commands.RetryTask do
  @moduledoc "Ask the agent to retry the current task."
  @derive Jason.Encoder
  defstruct command_type: "retry-task", reason: nil
  @type t :: %__MODULE__{command_type: String.t(), reason: String.t()}
end

defmodule Guava.Commands.SetVariable do
  @moduledoc "Store a JSON-serializable call-scoped variable."
  @derive Jason.Encoder
  defstruct command_type: "set-variable", key: nil, value: nil
  @type t :: %__MODULE__{command_type: String.t(), key: String.t(), value: term()}
end

defmodule Guava.Commands.SendCallerText do
  @moduledoc "Send a text message to the caller."
  @derive Jason.Encoder
  defstruct command_type: "send-caller-text", text: nil
  @type t :: %__MODULE__{command_type: String.t(), text: String.t()}
end

defmodule Guava.Commands.ExpertError do
  @moduledoc "Inform the agent that a developer callback errored."
  @derive Jason.Encoder
  defstruct command_type: "expert-error", message: nil
  @type t :: %__MODULE__{command_type: String.t(), message: String.t()}
end

defmodule Guava.Commands.SetAgentDTMF do
  @moduledoc "Enable or disable the agent's ability to press DTMF digits."
  @derive Jason.Encoder
  defstruct command_type: "set-agent-dtmf", enabled: false
  @type t :: %__MODULE__{command_type: String.t(), enabled: boolean()}
end

defmodule Guava.Commands.SendAgentDTMF do
  @moduledoc "Press a sequence of DTMF digits non-agentically."
  @derive Jason.Encoder
  defstruct command_type: "send-agent-dtmf", digits: []
  @type t :: %__MODULE__{command_type: String.t(), digits: [String.t()]}
end
