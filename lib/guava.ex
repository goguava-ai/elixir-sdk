defmodule Guava do
  @moduledoc """
  The Elixir SDK for the [Guava](https://goguava.ai) voice-agent platform.

  Two layers:

    * `Guava.Client` — account-level HTTP operations (phone numbers, SMS,
      outbound-call creation, campaigns).
    * `Guava.Agent` — a behaviour for handling live voice calls. Define an agent
      module, then attach it to a channel with `Guava.Channel` (supervised) or the
      blocking helpers here (`listen_phone/3`, `call_phone/5`, …) for scripts.

  See the `README` and the guides under `docs/`.
  """

  @typedoc "An E.164 formatted phone number, e.g. `\"+14155550123\"`."
  @type phone_number :: String.t()

  @doc """
  Start one or more `Guava.Channel` child specs under a supervisor and block
  until they stop. For scripts/`mix run`; in an app, add the child specs to your
  own supervision tree instead.

      Guava.run({Guava.Channel, agent: MyAgent, listen: {:phone, "+14155550123"}})
  """
  @spec run(Supervisor.child_spec() | [Supervisor.child_spec()]) :: :ok
  def run(children) do
    {:ok, sup} = Supervisor.start_link(List.wrap(children), strategy: :one_for_one)
    ref = Process.monitor(sup)

    receive do
      {:DOWN, ^ref, :process, ^sup, _} -> :ok
    end
  end

  @doc "Listen for inbound phone calls on `agent_number`. Blocks."
  @spec listen_phone(module(), phone_number(), keyword()) :: :ok
  def listen_phone(agent, agent_number, opts \\ []),
    do: block_channel(agent, [listen: {:phone, agent_number}], opts)

  @doc "Listen for inbound WebRTC calls (creates a code when `nil`). Blocks."
  @spec listen_webrtc(module(), String.t() | nil, keyword()) :: :ok
  def listen_webrtc(agent, webrtc_code \\ nil, opts \\ []),
    do: block_channel(agent, [listen: {:webrtc, webrtc_code}], opts)

  @doc "Listen for inbound SIP calls on `sip_code`. Blocks."
  @spec listen_sip(module(), String.t(), keyword()) :: :ok
  def listen_sip(agent, sip_code, opts \\ []),
    do: block_channel(agent, [listen: {:sip, sip_code}], opts)

  @doc "Serve an outbound campaign by code. Blocks."
  @spec attach_campaign(module(), String.t(), keyword()) :: :ok
  def attach_campaign(agent, campaign_code, opts \\ []),
    do: block_channel(agent, [campaign: campaign_code], opts)

  @doc "Place an outbound call and handle it with `agent`. Blocks until the call ends."
  @spec call_phone(module(), phone_number(), phone_number(), map(), keyword()) :: :ok
  def call_phone(agent, from_number, to_number, variables \\ %{}, opts \\ []) do
    client = opts[:client] || Guava.Client.new!()

    {:ok, pid} =
      Guava.Channel.Worker.start_link(
        agent: agent,
        client: client,
        mode: {:outbound, from_number, to_number, variables}
      )

    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    end
  end

  defp block_channel(agent, mode_opts, opts) do
    {:ok, sup} = Guava.Channel.start_link([agent: agent] ++ mode_opts ++ opts)
    ref = Process.monitor(sup)

    receive do
      {:DOWN, ^ref, :process, ^sup, _} -> :ok
    end
  end
end
