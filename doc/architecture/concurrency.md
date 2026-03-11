# Concurrency

How the plugin coordinates asynchronous agent I/O with synchronous Neovim API calls. Threading boundaries, callback scheduling, and the invariants that make concurrent buffer mutation impossible. Module signatures are in [Module Interfaces](module-interfaces.md), types in [Data Structures](data-structures.md), and the sequence diagrams in [Data Flow](data-flow.md).

## Threading Model

```
  libuv I/O thread                          Neovim main loop
 ─────────────────────                     ─────────────────────
  stdout read callback                      vim.schedule queue
  ┌──────────────────┐                     ┌──────────────────┐
  │ raw bytes arrive  │──vim.schedule──────►│ on_notification  │
  │ from agent stdio  │                     │ on_request       │
  │                   │                     │ on_error         │
  └──────────────────┘                     └────────┬─────────┘
                                                    │
  stderr / exit                                     ▼
  ┌──────────────────┐                     ┌──────────────────┐
  │ process signals   │──vim.schedule──────►│ on_exit          │
  └──────────────────┘                     │ dispatch + render │
                                           │ buffer writes     │
                                           └──────────────────┘
```

`Rpc.new` spawns the agent via `vim.system` and reads stdout on libuv's I/O thread. Every parsed message is handed to the main loop through `vim.schedule`. Everything downstream of a callback — dispatch, data mutation, buffer write — runs synchronously within a single `vim.schedule` tick. No Neovim API calls happen on the I/O thread; no concurrent buffer mutations are possible.

## Callback Scheduling

The four `RpcCallbacks` entry points and when they fire:

| Callback | Trigger | Scheduling |
|---|---|---|
| `on_notification` | Agent sends a JSON-RPC notification (`session/update`) | `vim.schedule` |
| `on_request` | Agent sends a JSON-RPC request (`session/request_permission`) | `vim.schedule` |
| `on_error` | Malformed message or parse failure on stdout | `vim.schedule` |
| `on_exit` | Agent process terminates (clean shutdown or crash) | `vim.schedule` |

All four are defined in [RpcCallbacks](module-interfaces.md#rpc) and bound during `Rpc.new`. The scheduling guarantee means every callback body can call `nvim_buf_set_lines`, `vim.ui.select`, or any other API function without wrapping.

## Streaming Update Serialization

Path from raw agent bytes to buffer pixels during a `session/update` notification:

1. libuv I/O thread reads bytes from agent stdout, accumulates in `rpc.buf`
2. Content-Length parser extracts a complete JSON-RPC message
3. `vim.schedule` — async boundary
4. `on_notification` fires → `session` calls `acp.dispatch_update(raw)` → returns `{kind, data}`
5. `session` routes to the data module: `conversation:append_message`, `conversation:update_tool_call`, or `plan:set`
6. `session` calls the buffer operation: `buffer:update_conversation` or `buffer:patch_tool_call`

Steps 4–6 execute atomically within one `vim.schedule` callback. No interleaving is possible: the next notification cannot dispatch until the current callback returns. This guarantees that data module state and buffer content are always consistent — a partial data mutation never reaches the screen.

The buffer has [two render paths](data-flow.md#render-path): full re-render for message chunks and new tool calls, extmark patch for `tool_call_update` streaming.

## Permission Request Lifecycle

Unlike streaming updates (single-tick), permission handling spans multiple ticks:

| Tick | Event | Action |
|---|---|---|
| 1 | `on_request("session/request_permission", params, respond)` | Store `PermissionState{request_id, tool_call, options}`, capture `respond` closure. Call `buffer:show_permission`. |
| 2..N-1 | `on_notification("session/update", ...)` | Streaming updates continue normally. Data and buffer updates interleave with the pending permission. |
| N | User presses `<CR>` | `buffer` fires `on_respond(option_id)` → `session` calls `acp.permission_outcome("selected", option_id)` → `rpc:respond(id, outcome)` → `buffer:clear_permission`. |

The `respond` closure captures the JSON-RPC request ID from tick 1. Between tick 1 and tick N, streaming updates arrive and process normally — the permission UI coexists with conversation rendering.

Cancellation: `session:cancel` checks for pending `PermissionState`, responds with `acp.permission_outcome("cancelled")` before sending `session/cancel`.

## Startup Sequencing

Each step is an async `rpc:request` whose callback fires on `vim.schedule` and chains the next:

```
Session.new(config)
  │
  ▼
Rpc.new(cmd, args, env, cwd, callbacks)  ──spawn──►  agent process
  │
  ▼
rpc:request("initialize")
  │ callback
  ▼
rpc:request("session/list")
  │ callback (session resolution)
  ▼
rpc:request("session/new") or rpc:request("session/load")
  │ callback
  ▼
Buffer.new(config) → buffer:show()
```

No step begins until its predecessor's callback fires. The chain is four ticks deep for the common path (initialize → list → new/load → show). See [Data Flow — Startup](data-flow.md#startup) for the full sequence diagram.

## Shutdown Ordering

Clean shutdown cascade:

```
init:stop()
  │
  ▼
session:stop()
  │
  ├──► rpc:shutdown()  ──EOF on stdin──►  agent process
  │         │
  │         ▼
  │    on_exit(code, signal)
  │
  └──► buffer:destroy()
```

`rpc:shutdown` sends EOF on stdin and waits for the process to exit, then fires `on_exit`. `buffer:destroy` wipes both the conversation and plan buffers.

`DirChanged` autocommand triggers the same `init:stop` path. Unexpected agent termination (crash, signal) skips the EOF step — libuv detects the exit and delivers `on_exit` via `vim.schedule`, converging on the same cleanup.

## State Mutation Safety

Per-module mutation patterns and the invariant that protects each:

| Module | Mutation pattern | Safety mechanism |
|---|---|---|
| `conversation` | Append-only blocks, indexed tool call patches | Single-threaded: all mutations run inside `vim.schedule` callbacks. Append order = render order. |
| `plan` | Complete replacement on each update | No diffing or merging — `plan:set` overwrites the entire entry list. |
| `config` | Immutable after `setup` | `config.get()` returns a frozen table; callers must not mutate it. |
| `render` | No state | Pure functions: data in, `string[]` out. No side effects. |
| `buffer` | Buffer writes via `nvim_buf_set_lines` | All writes gated by `vim.schedule`. Extmark ranges track through mutations. |
| `session` | Field assignment (`session_id`, `agent_state`, `permission`) | Single owner, single thread. No shared references across modules. |

## Single-Instance Constraint

`init` holds at most one `Session` reference. Each session owns exactly one `Rpc`, one `Conversation`, one `Plan`, and one `Buffer`. There is no multi-buffer synchronization, no shared mutable state between sessions, and no concurrent session instances.

`:Symbiont new` calls `session:stop()` on the existing session before creating a fresh one. `:Symbiont switch` reuses the existing RPC connection — it sends `session/load` to change the agent-side session, clears local state, and replays history into the same module instances.
