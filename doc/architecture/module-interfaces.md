# Module Interfaces

## rpc (`lua/symbiont/client/rpc.lua`)

Leaf module. NDJSON codec for JSON-RPC 2.0 messages. Defines generic wire types (`symbiont.rpc.Message`, `symbiont.rpc.Request`, `symbiont.rpc.Notification`, `symbiont.rpc.Response`, `symbiont.rpc.Error`). Module-level decode buffer.

### `rpc.encode(msg: symbiont.rpc.Message) → string`

JSON-encodes `msg`, appends newline. Pure function.

### `rpc.decode(chunk: string) → symbiont.rpc.Message[], string[]`

Appends `chunk` to internal buffer, extracts complete NDJSON lines, returns decoded messages and error strings. Buffer retains incomplete trailing data across calls.

## client (`lua/symbiont/client.lua`)

Depends on `rpc`, `acp`, `decode`, `encode`, `session`. Owns the agent process lifecycle, sessions, message routing, and pending request dispatch.

### `M.new(command: string[], on_exit: fun(client, code, signal)) → symbiont.Client?, string?`

Spawns the agent process, sends `initialize`, returns initialized client. Wires stdout through `rpc.decoder()` and dispatches decoded messages inside `vim.schedule`. Session update notifications route directly to session methods via `decode`. Permission requests route to `session:set_permission()`. Parse errors notify via `vim.notify`. On process exit, clears sessions and calls `on_exit` with the client reference.

### `client.sessions: table<string, symbiont.Session>`

Map of session_id to Session instances owned by this client. Populated by `session_new` and `session_load`. Cleared on process exit.

### `client:close()`

Kills the agent process.

### Session lifecycle

- `client:session_list(cwd?) → acp.ListSessionsResult` — async, sends `session/list` request
- `client:session_new(cwd) → symbiont.Session` — async, sends `session/new`, creates Session, stores in `sessions`
- `client:session_load(session_id, cwd) → symbiont.Session` — async, sends `session/load`, creates Session, stores in `sessions`

### Session-scoped protocol methods

- `client:prompt(session_id, contents)` — encodes contents to wire format, sends `session/prompt`
- `client:set_mode(session_id, mode_id)` — sends `session/setMode`
- `client:set_config_option(session_id, config_option_id, value)` — sends `session/setConfigOption`
- `client:cancel(session_id)` — sends `session/cancel` notification
- `client:permission_selected(request_id, option_id)` — sends permission response
- `client:permission_cancelled(request_id)` — sends permission cancellation

## session (`lua/symbiont/session.lua`)

Depends on `conversation`, `plan`, `mode`, `buffer`, `render`. Holds all state for a single session and delegates outbound RPC to its client.

### `M.new(session_id: string, client: symbiont.Client) → symbiont.Session`

Creates a session with fresh conversation, plan, mode, and buffer. Stores client reference for RPC delegation.

### State mutation methods (called by client on incoming updates)

- `session:append_turn(turn)` — appends each content of `turn` to the conversation, opening or extending a turn matching `turn.role`; refreshes buffer
- `session:add_thought(thought)` — appends a thought content to the assistant turn (merging into a trailing thought block if present); refreshes buffer
- `session:update_tool_turn(turn)` — inserts a tool turn (or patches existing entries by id), refreshes buffer
- `session:update_tool_call(tool_id, fields)` — patches a single tool call in-place, refreshes buffer
- `session:set_permission(request)` — stores permission, refreshes buffer
- `session:resolve_permission()` — clears permission, refreshes buffer
- `session:set_plan(entries)` — replaces plan entries
- `session:set_mode(mode_id)` — updates current mode

### RPC delegation methods (called by commands)

- `session:prompt(contents)` — delegates to `client:prompt(session_id, contents)`
- `session:cancel()` — delegates to `client:cancel(session_id)`
- `session:permission_selected(request_id, option_id)` — delegates to client
- `session:permission_cancelled(request_id)` — delegates to client

### Display

- `session:show()` — shows the buffer in a window
- `session:clear()` — resets all state and clears buffer
