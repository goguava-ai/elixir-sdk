defmodule Guava.DialerEvents.ControllerReady do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "controller-ready", call_id: nil
end

defmodule Guava.DialerEvents.InitControllerFailed do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "init-controller-failed", call_id: nil
end

defmodule Guava.DialerEvents.ListenStarted do
  @moduledoc false
  defstruct message_type: "listen-started", other_listeners: 0
end

defmodule Guava.DialerEvents.InitiateAndAssignCall do
  @moduledoc false
  defstruct message_type: "initiate-and-assign-call", call_id: nil, contact_data: nil
end

defmodule Guava.DialerEvents do
  @moduledoc false
  # Protocol for the campaign-serving socket (v1/serve-campaign).

  alias Guava.DialerEvents.{InitiateAndAssignCall, ListenStarted}

  @doc "Decode a server message map."
  def decode(%{"message_type" => "listen-started"} = m),
    do: %ListenStarted{other_listeners: m["other_listeners"]}

  def decode(%{"message_type" => "initiate-and-assign-call"} = m),
    do: %InitiateAndAssignCall{call_id: m["call_id"], contact_data: m["contact_data"]}
end
