# Deployment

## The application

The SDK is an OTP application that starts automatically with your app. Its
supervision tree includes a task supervisor, a registry of live calls
(`Guava.CallRegistry`), a `DynamicSupervisor` for call runtimes
(`Guava.CallSupervisor`), and the opt-in usage reporter (`Guava.Usage`). Just add
`:guava` as a dependency.

## Running channels

Add `Guava.Channel` child specs to your own supervision tree so they restart if
they exit:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Guava.Channel, agent: MyApp.SalesAgent, listen: {:phone, System.fetch_env!("SALES_NUMBER")}},
      {Guava.Channel, agent: MyApp.SurveyAgent, campaign: "camp_abc"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Each live call runs in its own process under `Guava.CallSupervisor`; a crash in
one call doesn't affect others. For scripts, the blocking `Guava.run/1` and
`Guava.listen_phone/3` helpers start the same machinery and block.

## Configuration

```elixir
# config/runtime.exs
config :guava,
  api_key: System.get_env("GUAVA_API_KEY"),
  usage_telemetry: false   # default; set true to opt in to usage reporting
```

In containers, the Guava-deploy token at `/var/run/secrets/guava/token` is picked
up automatically.

## Fault tolerance

- Callbacks run serially per call and are wrapped in try/rescue — a raising
  handler is logged and answered with a safe fallback, never dropping the call.
- The WebSocket transport reconnects with backoff and retransmits unacked
  messages across reconnects, so transient network blips are transparent.

## Observability

The SDK emits `:telemetry` events you can attach handlers to:

  * `[:guava, :http, :request, :start | :stop | :exception]`
  * `[:guava, :command, :sent]`

Each call process sets `Logger.metadata(call_id: ...)` for correlated logs.

```elixir
:telemetry.attach("guava-http", [:guava, :http, :request, :stop], &MyApp.Metrics.handle/4, nil)
```

## Publishing this library

`mix docs` generates the HTML API reference from the moduledocs and includes
these guides as extras.
