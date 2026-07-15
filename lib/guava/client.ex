defmodule Guava.PhoneNumberInfo do
  @moduledoc "Information about a phone number on your Guava account."
  defstruct [:phone_number]
  @type t :: %__MODULE__{phone_number: String.t()}
end

defmodule Guava.Client do
  @moduledoc """
  Account-level client for Guava's HTTP API.

  Handles authentication, phone numbers, SMS, outbound-call creation, and
  agent-code provisioning. Realtime call handling is done via `Guava.Agent`.

  ## Authentication

      # Explicit key
      client = Guava.Client.new(api_key: "gva-...")

      # From the GUAVA_API_KEY env var, a deploy token, or a CLI session
      {:ok, client} = Guava.Client.new()
  """

  alias Guava.{HTTP, PhoneNumberInfo, Error}

  @enforce_keys [:base_url, :auth]
  defstruct base_url: nil, auth: nil, req_options: []

  @type t :: %__MODULE__{base_url: String.t(), auth: Guava.Auth.t(), req_options: keyword()}
  @type result(x) :: {:ok, x} | {:error, Error.t()}

  @doc """
  Build a client, returning `{:ok, client} | {:error, %Guava.Error{}}`.

  ## Options

    * `:api_key` — explicit API key. Falls back to `config :guava, api_key:`,
      the deploy token file, the `GUAVA_API_KEY` env var, then a CLI session.
    * `:base_url` — override the API base URL.
    * `:req_options` — extra `Req` options merged into every request (mainly
      for testing, e.g. `plug:`).
  """
  @spec new(keyword()) :: result(t())
  def new(opts \\ []), do: Error.wrap(fn -> new!(opts) end)

  @doc "Like `new/1`, but raises `Guava.Error` when credentials can't be resolved."
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    %__MODULE__{
      base_url: opts[:base_url] || Guava.Config.base_url(),
      auth: Guava.Auth.resolve(opts[:api_key]),
      req_options: opts[:req_options] || []
    }
  end

  @doc "Return the resolved HTTP base URL for `path`."
  @spec http_url(t(), String.t()) :: String.t()
  def http_url(client, path), do: HTTP.http_url(client, path)

  @doc "Return the resolved WebSocket URL for `path`."
  @spec websocket_url(t(), String.t()) :: String.t()
  def websocket_url(client, path), do: HTTP.ws_url(client, path)

  @doc """
  Create a WebRTC agent code for browser connectivity. `ttl_seconds` optionally
  sets an expiry.
  """
  @spec create_webrtc_agent(t(), pos_integer() | nil) :: result(String.t())
  def create_webrtc_agent(client, ttl_seconds \\ nil),
    do: Error.wrap(fn -> create_webrtc_agent!(client, ttl_seconds) end)

  @spec create_webrtc_agent!(t(), pos_integer() | nil) :: String.t()
  def create_webrtc_agent!(client, ttl_seconds \\ nil) do
    params = if ttl_seconds, do: [ttl_sec: ttl_seconds], else: []
    HTTP.request!(client, :post, "v1/webrtc-agents", params: params)["webrtc_code"]
  end

  @doc "Create a SIP agent code."
  @spec create_sip_agent(t()) :: result(String.t())
  def create_sip_agent(client), do: Error.wrap(fn -> create_sip_agent!(client) end)

  @spec create_sip_agent!(t()) :: String.t()
  def create_sip_agent!(client), do: HTTP.request!(client, :post, "v1/sip-agents")["sip_code"]

  @doc """
  Low-level helper: create an outbound call and return its `call_id` without
  attaching an agent. Most code should instead place the call *and* run an agent
  on it in one step, with `Guava.run/1` and a `Guava.Channel` outbound listener:

      Guava.run({Guava.Channel, agent: MyAgent, outbound: {from, to, %{}}})
  """
  @spec create_outbound(t(), String.t(), String.t()) :: result(String.t())
  def create_outbound(client, from_number, to_number),
    do: Error.wrap(fn -> create_outbound!(client, from_number, to_number) end)

  @spec create_outbound!(t(), String.t(), String.t()) :: String.t()
  def create_outbound!(client, from_number, to_number) do
    HTTP.request!(client, :post, "v2/create-outbound",
      params: [from_number: from_number, to_number: to_number]
    )["call_id"]
  end

  @doc "List the phone numbers on your account."
  @spec list_numbers(t()) :: result([PhoneNumberInfo.t()])
  def list_numbers(client), do: Error.wrap(fn -> list_numbers!(client) end)

  @spec list_numbers!(t()) :: [PhoneNumberInfo.t()]
  def list_numbers!(client) do
    client
    |> HTTP.request!(:get, "v1/phone-numbers")
    |> Enum.map(&%PhoneNumberInfo{phone_number: &1["phone_number"]})
  end

  @doc "Send an outbound SMS."
  @spec send_sms(t(), String.t(), String.t(), String.t()) :: result(:ok)
  def send_sms(client, from_number, to_number, message),
    do: Error.wrap(fn -> send_sms!(client, from_number, to_number, message) end)

  @spec send_sms!(t(), String.t(), String.t(), String.t()) :: :ok
  def send_sms!(client, from_number, to_number, message) do
    HTTP.request!(client, :post, "v1/send-sms",
      json: %{from_number: from_number, to_number: to_number, message: message}
    )

    :ok
  end

  @doc """
  Wait for and return the next inbound SMS from `from_number` to `to_number`.

  Polls the inbox for messages received after this call begins, blocking until
  one arrives or `:timeout` elapses. Returns `{:ok, message | nil}` (`nil` on
  timeout) or `{:error, %Guava.Error{}}`.

  ## Options
    * `:timeout` — max seconds to wait (default `60.0`).
    * `:poll_interval` — seconds between polls (default `2.0`).
  """
  @spec next_sms(t(), String.t(), String.t(), keyword()) :: result(map() | nil)
  def next_sms(client, from_number, to_number, opts \\ []),
    do: Error.wrap(fn -> next_sms!(client, from_number, to_number, opts) end)

  @spec next_sms!(t(), String.t(), String.t(), keyword()) :: map() | nil
  def next_sms!(client, from_number, to_number, opts \\ []) do
    timeout = opts[:timeout] || 60.0
    poll_interval = opts[:poll_interval] || 2.0
    start = DateTime.utc_now() |> DateTime.to_iso8601()
    deadline = System.monotonic_time(:millisecond) + round(timeout * 1000)

    poll_next_sms(client, from_number, to_number, start, deadline, round(poll_interval * 1000))
  end

  defp poll_next_sms(client, from_number, to_number, start, deadline, poll_ms) do
    body =
      HTTP.request!(client, :get, "v1/messages",
        params: [to_number: to_number, from_number: from_number, modality: "sms", start: start]
      )

    case body["messages"] do
      [msg | _] ->
        msg

      _ ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          nil
        else
          Process.sleep(min(poll_ms, remaining))
          poll_next_sms(client, from_number, to_number, start, deadline, poll_ms)
        end
    end
  end

  @doc """
  Check whether this SDK version is deprecated. Returns the server's
  `deprecation_status` string (e.g. `"supported"`).
  """
  @spec check_sdk_deprecation(t()) :: result(String.t())
  def check_sdk_deprecation(client), do: Error.wrap(fn -> check_sdk_deprecation!(client) end)

  @spec check_sdk_deprecation!(t()) :: String.t()
  def check_sdk_deprecation!(client) do
    HTTP.request!(client, :post, "v1/check-sdk-deprecation",
      params: [sdk_name: HTTP.sdk_name(), sdk_version: HTTP.sdk_version()]
    )["deprecation_status"]
  end
end
