defmodule Guava.ListenInbound.ClaimCall do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "claim-call", call_id: nil
end

defmodule Guava.ListenInbound.AnswerCall do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "answer-call", call_id: nil
end

defmodule Guava.ListenInbound.DeclineCall do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "decline-call", call_id: nil
end

defmodule Guava.ListenInbound.ListenStarted do
  @moduledoc false
  defstruct message_type: "listen-started", other_listeners: 0
end

defmodule Guava.ListenInbound.IncomingCall do
  @moduledoc false
  defstruct message_type: "incoming-call", call_id: nil
end

defmodule Guava.ListenInbound.AssignCall do
  @moduledoc false
  defstruct message_type: "assign-call", call_id: nil, call_info: nil
end

defmodule Guava.ListenInbound do
  @moduledoc false
  # Protocol for the inbound-listener socket (v2/listen-inbound).

  alias Guava.ListenInbound.{AssignCall, IncomingCall, ListenStarted}

  @doc "Decode a server message map."
  def decode(%{"message_type" => "listen-started"} = m),
    do: %ListenStarted{other_listeners: m["other_listeners"]}

  def decode(%{"message_type" => "incoming-call"} = m),
    do: %IncomingCall{call_id: m["call_id"]}

  def decode(%{"message_type" => "assign-call"} = m),
    do: %AssignCall{call_id: m["call_id"], call_info: Guava.CallInfo.from_map(m["call_info"])}
end
