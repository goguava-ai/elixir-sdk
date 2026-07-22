defmodule Guava.Call do
  @moduledoc """
  A handle to a live call, passed to your `Guava.Agent` handlers.

  Use it to steer the conversation: assign tasks, set the persona, send
  instructions, transfer, read collected fields, and more. Every mutating
  function enqueues a command on the call's WebSocket connection.
  """
  require Logger

  alias Guava.Call.Runtime
  alias Guava.{Field, SerializableField, Say, Todo}

  alias Guava.Commands.{
    SetTask,
    SetPersona,
    SetLanguageMode,
    SetAgentDTMF,
    SendAgentDTMF,
    SendInstruction,
    Transfer,
    RetryTask,
    ReadScript,
    SetVariable
  }

  @enforce_keys [:id, :call_info, :server, :table]
  defstruct [:id, :call_info, :server, :table]

  @type t :: %__MODULE__{
          id: String.t(),
          call_info: Guava.CallInfo.t(),
          server: pid(),
          table: :ets.tid()
        }

  @default_reach_person_outcomes [
    %{key: "available", description: "The intended contact is confirmed on the line."},
    %{
      key: "unavailable",
      description:
        "The contact could not be reached. A third party, gatekeeper, or IVR was unable to transfer the call to the contact."
    },
    %{key: "voicemail", description: "An answering machine or voicemail system was reached."},
    %{key: "wrong_number", description: "The number does not reach the intended contact."},
    %{
      key: "do_not_contact",
      description: "The person on the line has indicated this number should not be called."
    }
  ]

  @doc "The default set of `reach_person` outcomes."
  def default_reach_person_outcomes, do: @default_reach_person_outcomes

  @doc "The call's session id."
  @spec id(t()) :: String.t()
  def id(%__MODULE__{id: id}), do: id

  @doc "The call's `Guava.CallInfo`."
  @spec call_info(t()) :: Guava.CallInfo.t()
  def call_info(%__MODULE__{call_info: ci}), do: ci

  @doc "Send an arbitrary command struct on this call."
  @spec send_command(t(), struct()) :: :ok
  def send_command(%__MODULE__{server: server}, command), do: Runtime.emit(server, command)

  @doc "Send a free-form instruction to steer the agent."
  @spec send_instruction(t(), String.t()) :: :ok
  def send_instruction(call, instruction),
    do: send_command(call, %SendInstruction{instruction: instruction})

  @doc "Store a JSON-serializable, call-scoped variable."
  @spec set_variable(t(), String.t(), term()) :: :ok
  def set_variable(%__MODULE__{table: table} = call, key, value) do
    unless jsonable?(value) do
      raise ArgumentError, "Variable value for key '#{key}' must be JSON-serializable."
    end

    :ets.insert(table, {{:var, key}, value})
    send_command(call, %SetVariable{key: key, value: value})
  end

  @doc "Read a call-scoped variable."
  @spec get_variable(t(), String.t(), term()) :: term()
  def get_variable(%__MODULE__{table: table}, key, default \\ nil) do
    case :ets.lookup(table, {:var, key}) do
      [{_, v}] -> v
      [] -> default
    end
  end

  @doc "Read a collected field value by key."
  @spec get_field(t(), String.t(), term()) :: term()
  def get_field(%__MODULE__{table: table}, key, default \\ nil) do
    case :ets.lookup(table, {:field, key}) do
      [{_, v}] -> v
      [] -> default
    end
  end

  @doc "Whether a field has been collected."
  @spec has_field?(t(), String.t()) :: boolean()
  def has_field?(%__MODULE__{table: table}, key), do: :ets.member(table, {:field, key})

  @doc "Set primary and secondary spoken languages."
  @spec set_language_mode(t(), String.t(), [String.t()]) :: :ok
  def set_language_mode(call, primary \\ "english", secondary \\ []),
    do: send_command(call, %SetLanguageMode{primary: primary, secondary: secondary})

  @doc "Enable or disable the agent pressing DTMF digits. Not supported on WebRTC calls."
  @spec set_agent_dtmf(t(), boolean()) :: :ok
  def set_agent_dtmf(call, enabled) do
    ensure_dtmf_supported!(call)
    send_command(call, %SetAgentDTMF{enabled: enabled})
  end

  @doc """
  Press a sequence of DTMF digits on the call (e.g. to navigate an IVR).

  `digits` may be a string like `"123"` or a list of single-digit strings. Each
  digit must be a valid DTMF digit (see `Guava.Types.dtmf_digits/0`). Not supported
  on WebRTC calls.
  """
  @spec send_dtmf(t(), String.t() | [String.t()]) :: :ok
  def send_dtmf(call, digits) do
    ensure_dtmf_supported!(call)
    digit_list = if is_binary(digits), do: String.graphemes(digits), else: digits

    unless Enum.all?(digit_list, &(&1 in Guava.Types.dtmf_digits())) do
      raise ArgumentError,
            "Please input valid DTMF digits. Valid digits are: #{inspect(Guava.Types.dtmf_digits())}."
    end

    send_command(call, %SendAgentDTMF{digits: digit_list})
  end

  @doc """
  Set the agent's persona.

  ## Options
  `:organization_name`, `:agent_name`, `:agent_purpose`, `:voice`.
  """
  @spec set_persona(t(), keyword()) :: :ok
  def set_persona(call, opts \\ []) do
    send_command(call, %SetPersona{
      agent_name: opts[:agent_name],
      organization_name: opts[:organization_name],
      agent_purpose: opts[:agent_purpose],
      voice: opts[:voice]
    })
  end

  @doc "Ask the agent to retry the current task."
  @spec retry_task(t(), String.t()) :: :ok
  def retry_task(call, reason), do: send_command(call, %RetryTask{reason: reason})

  @doc "Have the agent read a script verbatim."
  @spec read_script(t(), String.t()) :: :ok
  def read_script(call, script), do: send_command(call, %ReadScript{script: script})

  @doc "Provide the agent contextual information about a topic."
  @spec add_info(t(), String.t(), term()) :: :ok
  def add_info(call, label, info) do
    send_instruction(
      call,
      "Here is some information about the following topic #{label}:\n#{Jason.encode!(info, pretty: true)}"
    )
  end

  @doc """
  Transfer the call to a destination (phone number or SIP address).

  `instructions` (optional) tells the agent what to say; when omitted the
  agent announces a transfer before connecting. This is always a soft transfer.
  """
  @spec transfer(t(), String.t(), String.t() | nil) :: :ok
  def transfer(call, destination, instructions \\ nil) do
    send_command(call, %Transfer{
      transfer_message:
        instructions || "Notify the caller that you will be transferring them, and then transfer.",
      to_number: destination,
      soft_transfer: true
    })
  end

  @doc "Instruct the agent to naturally end the conversation and hang up."
  @spec hangup(t(), String.t()) :: :ok
  def hangup(call, final_instructions \\ "") do
    instructions =
      if final_instructions != "" do
        "Start ending the conversation. Here are your final instructions: #{final_instructions} " <>
          "Once you've completed the final instructions, naturally end the conversation and hang up the call."
      else
        "Naturally end the conversation and hang up the call."
      end

    send_instruction(call, instructions)
  end

  @doc """
  Assign a task: an objective and/or a checklist of items.

  Checklist items may be `Guava.Field` structs, `Guava.Say`, `Guava.Todo`, or
  plain strings (converted to todos).
  """
  @spec set_task(t(), String.t(), keyword()) :: :ok
  def set_task(call, task_id, opts \\ []) do
    objective = opts[:objective] || ""
    checklist = opts[:checklist] || []
    completion_criteria = opts[:completion_criteria]

    if objective == "" and checklist == [] do
      raise ArgumentError, "At least one of :objective or :checklist must be provided."
    end

    # Record which field keys belong to this task so their validators can run when
    # the task completes (see Guava.Call.Runtime).
    :ets.insert(call.table, {{:task_fields, task_id}, field_keys(checklist)})

    send_command(call, %SetTask{
      task_id: task_id,
      objective: objective,
      completion_criteria: completion_criteria,
      action_items: Enum.map(checklist, &to_action_item/1)
    })
  end

  defp field_keys(checklist) do
    for item <- checklist,
        match?(%Field{}, item) or match?(%SerializableField{}, item),
        do: item.key
  end

  defp ensure_dtmf_supported!(%__MODULE__{call_info: %{call_type: "webrtc"}}) do
    raise ArgumentError, "WebRTC calls do not support sending DTMF."
  end

  defp ensure_dtmf_supported!(_call), do: :ok

  defp to_action_item(item) when is_binary(item), do: Todo.new(item)
  defp to_action_item(%Field{} = f), do: SerializableField.from_field(f)
  defp to_action_item(%SerializableField{} = f), do: f
  defp to_action_item(%Say{} = s), do: s
  defp to_action_item(%Todo{} = t), do: t

  @doc """
  Reach a specific contact on an outbound call and record their availability
  in the `contact_availability` field. React to the outcome in
  `c:Guava.Agent.handle_task_complete/3` (task id `"reach_person"`), reading the
  `contact_availability` field with `get_field/2`.

  ## Options
    * `:greeting` — verbatim opening line.
    * `:voicemail_message` — leave this message on voicemail, then hang up.
    * `:voicemail_hangup` — hang up immediately on voicemail (no message).
    * `:outcomes` — override the availability outcomes (list of maps with
      `:key`, optional `:description`, optional `:next_action_preview`).
  """
  @spec reach_person(t(), String.t(), keyword()) :: :ok
  def reach_person(call, contact_full_name, opts \\ []) do
    outcomes = opts[:outcomes] || @default_reach_person_outcomes
    greeting = opts[:greeting]
    voicemail_message = opts[:voicemail_message]
    voicemail_hangup = opts[:voicemail_hangup] || false

    if voicemail_message && voicemail_hangup do
      raise ArgumentError, "Cannot specify both :voicemail_message and :voicemail_hangup."
    end

    availability_field_description = reach_person_description(contact_full_name, outcomes)
    voicemail_rule = voicemail_rule(voicemail_hangup, voicemail_message)
    objective = reach_person_objective(contact_full_name, voicemail_rule)

    completion_criteria =
      "\nTASK COMPLETION REQUIREMENTS:\n- The availability of #{contact_full_name} must be recorded in `contact_availability`.\n"

    greeting_item =
      if greeting do
        Say.new(greeting)
      else
        "Greet the person, IVR, or system who answered the phone. " <>
          "Notify them who you are calling on behalf of and the purpose of the call. " <>
          "Ask to speak with #{contact_full_name}. " <>
          "Do not greet if you detect an answering machine or voicemail system."
      end

    availability_field =
      Field.new(
        key: "contact_availability",
        description: availability_field_description,
        field_type: "multiple_choice",
        choices: Enum.map(outcomes, & &1.key),
        required: true
      )

    checklist = [greeting_item, availability_field] ++ next_action_lines(outcomes)

    set_task(call, "reach_person",
      objective: objective,
      checklist: checklist,
      completion_criteria: completion_criteria
    )
  end

  defp reach_person_description(name, outcomes) do
    base = "The availability of #{name}."

    lines =
      for o <- outcomes, Map.get(o, :description), do: " - #{o.key}: #{o.description}"

    if lines == [] do
      base
    else
      base <> "\nDetailed descriptions of each choice:\n" <> Enum.join(lines, "\n")
    end
  end

  defp next_action_lines(outcomes) do
    lines =
      for o <- outcomes,
          preview = Map.get(o, :next_action_preview),
          preview != nil,
          do: "- #{o.key} → #{preview}"

    if lines == [] do
      []
    else
      [
        "If a next action is defined below for the recorded value of `contact_availability`, " <>
          "briefly let the contact know while you perform it.\n" <> Enum.join(lines, "\n")
      ]
    end
  end

  defp voicemail_rule(true, _),
    do: "DO NOT leave a message. REMAIN SILENT AND HANG UP WITHOUT RESPONDING."

  defp voicemail_rule(false, msg) when is_binary(msg),
    do: "Say this message VERBATIM: \"#{msg}\" Then hang up."

  defp voicemail_rule(false, _), do: "Leave an appropriate voicemail message."

  defp reach_person_objective(name, voicemail_rule) do
    """

    OBJECTIVE:
    Your goal is to reach #{name} and confirm they are on the line.

    RULES:
    1. If someone other than #{name} answers - including a person or IVR:
       - Politely ask to speak with #{name}, or navigate menus and prompts to reach them.
       - Wait to be transferred or for #{name} to come to the phone.
       - If #{name} cannot be reached, record `contact_availability` appropriately.
    2. Once #{name} is confirmed on the line:
       - Briefly restate who you are and the purpose of your call
       - Record their availability as available, or equivalent, in `contact_availability`.
    3. If it is clearly a wrong number or you have been asked not to call, politely end the call and hang up.
    4. If you reach an answering machine or voicemail: #{voicemail_rule}
    """
  end

  defp jsonable?(value) do
    case Jason.encode(value) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
