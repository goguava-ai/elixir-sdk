# Messaging (SMS)

Send SMS and wait for replies with `Guava.Client`.

## Sending

```elixir
client = Guava.Client.new()
Guava.Client.send_sms!(client, "+14155550100", "+16285550123", "Your table is ready!")
```

Arguments are `from_number`, `to_number` (both E.164), and the message body.

## Waiting for a reply

`next_sms!/4` polls the inbox for the next message from `from_number` to
`to_number` that arrives *after the call begins*, blocking until one arrives or
the timeout elapses. Returns the message map, or `nil` on timeout.

```elixir
case Guava.Client.next_sms!(client, "+16285550123", "+14155550100", timeout: 60.0, poll_interval: 2.0) do
  nil -> IO.puts("no reply within the timeout")
  msg -> IO.puts("reply: #{msg["content"]}")
end
```

Note the argument order: `next_sms(client, from_number, to_number, opts)` waits
for a message **from** the external sender **to** one of your numbers.

The returned map includes `"id"`, `"from_number"`, `"to_number"`, `"content"`,
`"received_at"`, `"modality"`, and `"direction"`.

### A simple round-trip

```elixir
Guava.Client.send_sms!(client, ours, theirs, "Reply YES to confirm.")

case Guava.Client.next_sms!(client, theirs, ours, timeout: 120.0) do
  %{"content" => body} -> if String.upcase(body) =~ "YES", do: confirm(), else: :noop
  nil -> follow_up()
end
```

Options: `:timeout` (seconds, default `60.0`) and `:poll_interval` (seconds,
default `2.0`).

Next: [Client](client.md).
