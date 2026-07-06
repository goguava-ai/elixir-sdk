defmodule Guava.IncomingCallAction.Accept do
  @moduledoc "Accept an incoming call."
  @derive Jason.Encoder
  defstruct call_action: "accept"
  @type t :: %__MODULE__{call_action: String.t()}
end

defmodule Guava.IncomingCallAction.Decline do
  @moduledoc "Decline an incoming call."
  @derive Jason.Encoder
  defstruct call_action: "decline"
  @type t :: %__MODULE__{call_action: String.t()}
end

defmodule Guava.IncomingCallAction do
  @moduledoc """
  The action to take for an incoming call: accept or decline.

  Returned from an `on_call_received` handler. Use the `accept/0` and
  `decline/0` helpers, or the structs directly.
  """

  alias Guava.IncomingCallAction.{Accept, Decline}

  @type t :: Accept.t() | Decline.t()

  @doc "Accept the incoming call."
  @spec accept() :: Accept.t()
  def accept, do: %Accept{}

  @doc "Decline the incoming call."
  @spec decline() :: Decline.t()
  def decline, do: %Decline{}
end
