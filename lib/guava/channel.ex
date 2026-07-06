defmodule Guava.Channel.Worker do
  @moduledoc false
  # Owns one channel's socket and starts per-call runtimes under
  # Guava.CallSupervisor. Modes: {:listen, query}, {:campaign, campaign},
  # {:outbound, from, to, vars}.
  use GenServer
  require Logger

  alias Guava.{Socket, HTTP, CallInfo, ListenInbound, DialerEvents}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    client = Keyword.fetch!(opts, :client)
    Process.flag(:trap_exit, true)
    do_init(Keyword.fetch!(opts, :mode), agent, client)
  end

  defp do_init({:listen, query}, agent, client) do
    url = HTTP.ws_url(client, "v2/listen-inbound?" <> URI.encode_query(query))

    {:ok, sock} =
      Socket.start_link(
        url: url,
        name: "listen-inbound",
        headers: HTTP.headers(client),
        owner: self()
      )

    {:ok, %{mode: :listen, agent: agent, client: client, sock: sock}}
  end

  defp do_init({:campaign, campaign}, agent, client) do
    url = HTTP.ws_url(client, "v1/serve-campaign/#{campaign.id}")

    {:ok, sock} =
      Socket.start_link(
        url: url,
        name: "serve-campaign",
        headers: HTTP.headers(client),
        owner: self()
      )

    Logger.info("Connecting to campaign '#{campaign.name}' (id: #{campaign.id}).")
    {:ok, %{mode: :campaign, agent: agent, client: client, sock: sock, campaign: campaign}}
  end

  defp do_init({:outbound, from, to, vars}, agent, client) do
    call_id = Guava.Client.create_outbound!(client, from, to)
    Logger.info("Outbound call created with session ID: #{call_id}")
    call_info = %CallInfo.PSTN{from_number: from, to_number: to}
    {:ok, pid} = start_call(agent, client, call_id, call_info, vars, "v2/connect-call")
    {:ok, %{mode: :outbound, call_ref: Process.monitor(pid)}}
  end

  @impl true
  def handle_info({:guava_socket, _pid, :ready}, state), do: {:noreply, state}

  def handle_info({:guava_socket, _pid, {:payload, map}}, %{mode: :listen} = state) do
    handle_listen(ListenInbound.decode(map), state)
    {:noreply, state}
  end

  def handle_info({:guava_socket, _pid, {:payload, map}}, %{mode: :campaign} = state) do
    handle_campaign(DialerEvents.decode(map), state)
    {:noreply, state}
  end

  def handle_info({:guava_socket, _pid, {:closed, reason, _desc}}, state) do
    Logger.info("Channel socket closed: #{reason}")
    {:stop, :normal, state}
  end

  # Outbound: the single call finished → the channel is done.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{mode: :outbound, call_ref: ref} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---- listen protocol ----

  defp handle_listen(%ListenInbound.ListenStarted{other_listeners: n}, _state),
    do: Logger.info("Started listening. #{n} other listeners registered.")

  defp handle_listen(%ListenInbound.IncomingCall{call_id: call_id}, state),
    do: Socket.send_payload(state.sock, wire(%ListenInbound.ClaimCall{call_id: call_id}))

  defp handle_listen(%ListenInbound.AssignCall{call_id: call_id, call_info: call_info}, state) do
    case state.agent.handle_call_received(call_info) do
      :decline ->
        Logger.info("Declining call #{call_id}")
        Socket.send_payload(state.sock, wire(%ListenInbound.DeclineCall{call_id: call_id}))

      _accept ->
        Logger.info("Answering call #{call_id}")
        Socket.send_payload(state.sock, wire(%ListenInbound.AnswerCall{call_id: call_id}))
        start_call(state.agent, state.client, call_id, call_info, %{}, "v2/connect-call")
    end
  end

  # ---- campaign protocol ----

  defp handle_campaign(%DialerEvents.ListenStarted{}, _state),
    do: Logger.info("Listening for campaign calls. Ready.")

  defp handle_campaign(
         %DialerEvents.InitiateAndAssignCall{call_id: call_id, contact_data: data},
         state
       ) do
    to = data && data["phone_number"]
    vars = (data && data["data"]) || %{}
    call_info = %CallInfo.PSTN{from_number: nil, to_number: to}
    Socket.send_payload(state.sock, wire(%DialerEvents.ControllerReady{call_id: call_id}))
    start_call(state.agent, state.client, call_id, call_info, vars, "v2/connect-campaign-call")
  end

  defp start_call(agent, client, call_id, call_info, variables, route) do
    DynamicSupervisor.start_child(
      Guava.CallSupervisor,
      {Guava.Call.Runtime,
       [
         agent: agent,
         client: client,
         call_id: call_id,
         call_info: call_info,
         initial_variables: variables,
         route: route
       ]}
    )
  end

  defp wire(struct), do: struct |> Jason.encode!() |> Jason.decode!()
end

defmodule Guava.Channel do
  @moduledoc """
  A supervised channel connecting an agent module to callers. Use it as a child
  spec in your own supervision tree:

      children = [
        {Guava.Channel, agent: MyAgent, listen: {:phone, "+14155550123"}},
        {Guava.Channel, agent: Survey, campaign: "camp_abc"}
      ]

  Options:

    * `:agent` — the `Guava.Agent` module (required)
    * one of:
      * `listen: {:phone, number} | {:webrtc, code | nil} | {:sip, code}`
      * `campaign: campaign_code`
      * `outbound: {from_number, to_number, variables}`
    * `:client` — a `Guava.Client` (defaults to `Guava.Client.new!/0`)
    * `:name` — optional supervisor name
  """
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    client = opts[:client] || Guava.Client.new!()
    mode = resolve_mode(opts, client)

    children = [
      %{
        id: Guava.Channel.Worker,
        start: {Guava.Channel.Worker, :start_link, [[agent: agent, client: client, mode: mode]]},
        restart: :permanent
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def resolve_mode(opts, client) do
    cond do
      listen = opts[:listen] -> {:listen, listen_query(listen, client)}
      code = opts[:campaign] -> {:campaign, Guava.Campaigns.get_by_code!(client, code)}
      {from, to, vars} = opts[:outbound] -> {:outbound, from, to, vars}
    end
  end

  defp listen_query({:phone, number}, _client), do: [phone_number: number]
  defp listen_query({:sip, code}, _client), do: [sip_code: code]

  defp listen_query({:webrtc, nil}, client),
    do: [webrtc_code: Guava.Client.create_webrtc_agent!(client, 3600)]

  defp listen_query({:webrtc, code}, _client), do: [webrtc_code: code]
end
