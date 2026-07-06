defmodule Guava.CallInfo.PSTN do
  @moduledoc "A public-switched-telephone-network (phone) call."
  @derive Jason.Encoder
  defstruct call_type: "pstn", from_number: nil, to_number: nil, caller_id: nil

  @type t :: %__MODULE__{
          call_type: String.t(),
          from_number: String.t() | nil,
          to_number: String.t() | nil,
          caller_id: String.t() | nil
        }
end

defmodule Guava.CallInfo.WebRTC do
  @moduledoc "A browser (WebRTC) call."
  @derive Jason.Encoder
  defstruct call_type: "webrtc", webrtc_code: nil

  @type t :: %__MODULE__{call_type: String.t(), webrtc_code: String.t()}
end

defmodule Guava.CallInfo.Sip do
  @moduledoc "A SIP call."
  @derive Jason.Encoder
  defstruct call_type: "sip", from_aor: nil, sip_code: nil, sip_headers: %{}

  @type t :: %__MODULE__{
          call_type: String.t(),
          from_aor: String.t(),
          sip_code: String.t() | nil,
          sip_headers: %{String.t() => String.t()}
        }
end

defmodule Guava.CallInfo do
  @moduledoc """
  Information about an incoming or outgoing call.

  One of `Guava.CallInfo.PSTN`, `Guava.CallInfo.WebRTC`, or
  `Guava.CallInfo.Sip`, discriminated on the wire by `call_type`.
  """

  alias Guava.CallInfo.{PSTN, Sip, WebRTC}

  @type t :: PSTN.t() | WebRTC.t() | Sip.t()

  @doc "Decode a wire map into the matching call-info struct."
  @spec from_map(map()) :: t()
  def from_map(%{"call_type" => "pstn"} = m) do
    %PSTN{from_number: m["from_number"], to_number: m["to_number"], caller_id: m["caller_id"]}
  end

  def from_map(%{"call_type" => "webrtc"} = m) do
    %WebRTC{webrtc_code: m["webrtc_code"]}
  end

  def from_map(%{"call_type" => "sip"} = m) do
    %Sip{from_aor: m["from_aor"], sip_code: m["sip_code"], sip_headers: m["sip_headers"] || %{}}
  end
end
