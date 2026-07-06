defmodule Guava.Types do
  @moduledoc """
  Shared value types, enums, and validators used across the wire protocol.

  These mirror the constrained types in the Python SDK's `guava.types` module.
  """

  @typedoc "An E.164 phone number, e.g. `\"+14155550123\"`."
  @type e164 :: String.t()

  @typedoc "A DTMF keypad digit."
  @type dtmf_digit :: String.t()

  @typedoc "Reason a bot session ended."
  @type termination_reason ::
          :user_hangup | :bot_hangup | :bot_failure | :bot_transfer | :voicemail | String.t()

  @typedoc "Spoken language for the agent."
  @type language :: String.t()

  @typedoc "A structured-collection field type."
  @type field_type :: String.t()

  @e164_regex ~r/^\+[1-9]\d{1,14}$/

  @dtmf_digits ~w(0 1 2 3 4 5 6 7 8 9 * # A B C D)

  @termination_reasons ~w(user-hangup bot-hangup bot-failure bot-transfer voicemail)

  @languages ~w(english spanish french german italian)

  @field_types ~w(text date datetime integer multiple_choice calendar_slot)

  @outreach_modalities ~w(sms)

  @doc "Returns `true` when `value` is a valid E.164 phone number string."
  @spec valid_e164?(term()) :: boolean()
  def valid_e164?(value) when is_binary(value), do: Regex.match?(@e164_regex, value)
  def valid_e164?(_), do: false

  @doc "Raises `ArgumentError` unless `value` is a valid E.164 phone number."
  @spec validate_e164!(String.t()) :: String.t()
  def validate_e164!(value) do
    if valid_e164?(value) do
      value
    else
      raise ArgumentError,
            "expected an E.164 phone number matching #{inspect(@e164_regex.source)}, got: #{inspect(value)}"
    end
  end

  @doc "Valid DTMF digits."
  @spec dtmf_digits() :: [String.t()]
  def dtmf_digits, do: @dtmf_digits

  @doc "Valid termination reasons."
  @spec termination_reasons() :: [String.t()]
  def termination_reasons, do: @termination_reasons

  @doc "Supported languages."
  @spec languages() :: [String.t()]
  def languages, do: @languages

  @doc "Supported field types."
  @spec field_types() :: [String.t()]
  def field_types, do: @field_types

  @doc "Supported outreach modalities."
  @spec outreach_modalities() :: [String.t()]
  def outreach_modalities, do: @outreach_modalities
end
