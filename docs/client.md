# Client

`Guava.Client` handles account-level HTTP operations. `Guava.Agent` creates one
for you, but you can build and use it directly.

Every operation comes in two forms: the primary returns
`{:ok, result} | {:error, %Guava.Error{}}`, and a `!` variant raises.

```elixir
{:ok, client} = Guava.Client.new(api_key: "gva-...")
client = Guava.Client.new!()   # from config/env; raises on failure
```

See [Getting started](getting-started.md#authenticate) for credential
resolution and the `:base_url` / `:req_options` options.

## Phone numbers

```elixir
{:ok, numbers} = Guava.Client.list_numbers(client)
numbers = Guava.Client.list_numbers!(client)
# => [%Guava.PhoneNumberInfo{phone_number: "+14155550123"}, ...]
```

## Agent codes

Provision codes for browser (WebRTC) or SIP connectivity:

```elixir
{:ok, code} = Guava.Client.create_webrtc_agent(client)         # no expiry
code = Guava.Client.create_webrtc_agent!(client, 3600)         # expires in 1 hour
{:ok, sip} = Guava.Client.create_sip_agent(client)
```

## Outbound calls

`create_outbound/3` creates a call and returns its `call_id` without attaching a
handler. Most code should use [`Guava.call_phone/5`](channels.md#outbound)
instead, which creates *and* handles the call.

```elixir
{:ok, call_id} = Guava.Client.create_outbound(client, "+14155550100", "+16285550123")
```

## SMS

`send_sms/4` and `next_sms/4` (+ bang variants) — see [Messaging](messaging.md).

## Version / deprecation check

```elixir
{:ok, "supported"} = Guava.Client.check_sdk_deprecation(client)
```

Unlike the Python SDK, this port does **not** call the deprecation endpoint
automatically on client creation — invoke it yourself if you want the check.

## Errors

The tuple form returns `{:error, %Guava.Error{type: type, status: status, body: body}}`;
the `!` form raises the same `%Guava.Error{}`. `type` is `:http`, `:auth`,
`:transport`, or `:unknown`.

```elixir
case Guava.Client.create_sip_agent(client) do
  {:ok, code} -> code
  {:error, %Guava.Error{status: status, body: body}} -> Logger.error("Guava #{status}: #{body}")
end
```

## Testing without the network

Pass Req options through `:req_options` — handy for `Req.Test` stubs in your
own tests:

```elixir
client = Guava.Client.new!(api_key: "test", req_options: [plug: {Req.Test, MyStub}])
```

Next: [RAG & LLM helpers](rag-and-llm.md).
