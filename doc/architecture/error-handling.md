# Error Handling

How the plugin classifies, recovers from, and surfaces errors to the user. Threading and scheduling details are in [Concurrency](concurrency.md), message flow in [Data Flow](data-flow.md), callback signatures in [Module Interfaces](module-interfaces.md), and types in [Data Structures](data-structures.md).

## Error Classification

| Origin | Example | Handler | Recovery |
|---|---|---|---|
| Transport | Malformed JSON on stdout, truncated Content-Length frame | `on_error` callback | Reset `rpc.buf`, notify user, continue |
| RPC response | `error` object in a JSON-RPC response | Per-request callback `err` parameter | Depends on method (see below) |
| Process exit | Agent crash, signal, clean shutdown | `on_exit` callback | Drain `rpc.pending`, transition to `"closed"` |
| Agent-side | Tool call failure, refusal, token limit | None — not an error | Render as conversation data |

The plugin draws a sharp boundary between errors it **handles** and agent-side outcomes it merely **renders**. Anything that arrives as a well-formed JSON-RPC message body — including `ToolCallStatus = "failed"` or `StopReason = "refusal"` — is data, not an error. The plugin dispatches it through the normal conversation → buffer path. Error-handling code only runs when the transport, the RPC framing, or the process itself misbehaves.

## Transport Errors

```
libuv I/O thread              vim.schedule              session callbacks
─────────────────              ────────────              ─────────────────
stdout read ──►  parse fails
                     │
                     ▼
              vim.schedule(fn)  ──►  on_error(err)
                                         │
                                         ▼
                                  notification_handler(WARN, err, "transport")
```

When the rpc module fails to parse a message from stdout (malformed JSON, invalid Content-Length header), it resets `rpc.buf` and calls `on_error` via `vim.schedule`. The connection stays open — `rpc.state` remains unchanged and the plugin continues reading. There is no retry logic; the malformed message is lost and the user sees a warning through `notification_handler`. This matches the scheduling guarantee: `on_error` always fires on the main loop, so the handler can safely call Neovim API functions.

## RPC Response Errors

Each RPC method has a fixed recovery strategy based on whether it belongs to the startup chain or the runtime phase.

**Startup chain — fatal:**

| Method | On error |
|---|---|
| `initialize` | `rpc:shutdown()`, notify |
| `session/list` | `rpc:shutdown()`, notify |
| `session/new` | `rpc:shutdown()`, notify |
| `session/load` | `rpc:shutdown()`, notify |

**Runtime — non-fatal:**

| Method | On error |
|---|---|
| `session/prompt` | Notify, continue |
| `session/set_mode` | Notify, continue |

Startup errors are fatal because each step depends on the previous result — there is no useful state to fall back to. Runtime errors leave the session intact; the user can retry the operation.

When `on_exit` fires (whether from `rpc:shutdown()` or an unexpected termination), the rpc module iterates `rpc.pending` and calls each entry's `callback(err, nil)` with a process-exit error. This prevents leaked pending requests: every `Rpc:request` call is guaranteed to receive exactly one callback invocation.

## Process Lifecycle Errors

```
                  Rpc.new()          initialize succeeds      rpc:shutdown() / crash
                     │                       │                        │
                     ▼                       ▼                        ▼
               "connecting"  ──────►    "ready"    ──────►       "closed"
```

`rpc.state` is a one-way progression. Once `"closed"`, no further writes to stdin are attempted — `Rpc:request` and `Rpc:notify` become no-ops.

| Path | Trigger | EOF sent? | `on_exit` fires? | Pending drained? |
|---|---|---|---|---|
| Clean shutdown | `rpc:shutdown()` | Yes | Yes | Yes |
| Unexpected exit | Crash / signal | No | Yes | Yes |

Both paths converge on the same cleanup: `rpc.state` transitions to `"closed"`, every entry in `rpc.pending` receives an error callback, and `on_exit` fires exactly once via `vim.schedule`. The only difference is whether the plugin initiated the exit (EOF on stdin) or libuv detected it. See [Shutdown Ordering](concurrency.md#shutdown-ordering) for the full cascade.

## Notification Routing

Every user-facing error message in the plugin routes through `notification_handler`. The plugin never calls `vim.notify` directly.

| Return value | Effect |
|---|---|
| `"ignore"` | Message is silently dropped |
| `"notify"` | Message is forwarded to `vim.notify` |
| `"system"` | Message is appended to the conversation buffer as a system line |

This gives the host application a single interception point for all diagnostics — transport errors, RPC failures, and informational messages alike. The signature `fun(level: integer, msg: string, kind: string)` carries enough context for filtering by severity or origin. See [Extension Points](extension-points.md) for configuration details.

## Errors the Plugin Does Not Handle

These agent-side outcomes arrive inside well-formed `session/update` notifications and flow through the normal dispatch → conversation → buffer path. No error-specific code runs.

| Outcome | Source field | Values the plugin renders |
|---|---|---|
| Tool failure | `ToolCallStatus` | `"failed"` |
| Conversation end | `StopReason` | `"end_turn"`, `"max_tokens"`, `"max_turn_requests"`, `"refusal"`, `"cancelled"` |

A tool call with status `"failed"` is not a plugin error — it means the agent attempted an operation that did not succeed. The plugin renders it identically to any other tool call status. Similarly, `StopReason = "refusal"` is a normal conversation outcome, not an error condition the plugin needs to recover from.
