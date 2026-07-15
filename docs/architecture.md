# Architecture

Every Guava call involves two systems working in parallel:

- **The Dialog System** — Guava's hosted service. It handles telephony, speech
  recognition and synthesis, turn-taking, and the moment-to-moment conversation
  with the caller.
- **Your Expert** — the code you write with this SDK. It supplies knowledge,
  business logic, and decisions: answering questions, classifying intents,
  filling in structured data, transferring calls, and so on.

The two communicate over a realtime WebSocket connection. The Dialog System
sends your Expert **events** (the caller said something, a task finished, a
question needs answering); your Expert sends back **commands** (set a task,
transfer, send an instruction, answer a question).

```
   caller ──telephony──▶ Guava Dialog System ──events──▶  Your Expert (this SDK)
                              ▲                              │
                              └──────────── commands ────────┘
```

## How the Elixir SDK is structured

The SDK layers map onto that picture:

| Layer | Module(s) | Role |
| --- | --- | --- |
| Transport | `Guava.Socket`, `Guava.Socket.Reliable` | A reliable, self-reconnecting WebSocket with sequence numbers, acks, retransmission, and keepalive. |
| Wire protocol | `Guava.Events`, `Guava.Commands` | Byte-for-byte compatible encodings of the events/commands exchanged with the Dialog System. |
| Runtime | Guava.Call.Runtime *(internal)* | One OTP process per live call. Owns the socket + a per-call ETS table (fields/variables), threads your agent's state, and dispatches events to your callbacks. |
| Channels | `Guava.Channel`, `Guava.run/1` | Supervised listeners (phone/WebRTC/SIP/campaign/outbound) that start a runtime per call. |
| Your Expert | `Guava.Agent`, `Guava.Call` | The API you write against: a behaviour module + a handle to steer the call. |
| Account API | `Guava.Client`, `Guava.Campaigns` | HTTP operations: phone numbers, SMS, outbound creation, campaigns. |

Each call runs in its own supervised process. Your callbacks run **serially**
within that process (so per-call state can't race), while field/variable reads
go straight to ETS (so a callback can read without deadlocking). Offload slow
work to a `Task` and handle the result in `handle_info/3`. See
[`../PARITY.md`](../PARITY.md) for the idiomatic differences from the Python SDK.

## What you write

You almost always work at the `Guava.Agent` / `Guava.Call` level:

- **`Guava.Agent`** is a behaviour you `use` in a module: a persona plus the
  event callbacks you implement. Each call runs in its own process threading a
  per-call state. Attach the module to a channel.
- **`Guava.Call`** is a handle to one live call, passed into your handlers. You
  use it to assign tasks, transfer, read collected fields, and more.

Next: [Getting started](getting-started.md).
