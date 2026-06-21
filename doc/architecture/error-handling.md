# Error Handling

## Error Surfaces

Three distinct error channels handled internally by the client:

| Channel | Trigger | Handling |
|---|---|---|
| RPC error response | Response with `error` field for a pending request | Raises error in the waiting coop task via `coop_task.resume` |
| Parse error | Malformed JSON from agent stdout | `vim.notify` at WARN level |
| Process exit | Agent process terminates | Clears sessions, calls `on_exit(client, code, signal)` callback |

## Request/Response Dispatch

The client uses async/await via coop tasks. Each request stores the running task in `pending_requests[id]`. When the response arrives:

```
request(method, payload)
  pending_requests[id] = coop_task.running()
  send(payload)
  response = coop_task.yield()
  ...response arrives...
  ├─ success → coop_task.resume(task, response) → caller gets result
  └─ error   → coop_task.resume(task, response) → caller gets error(), propagates
```

Orphaned responses (unknown id) with an error field are logged via `vim.notify`. Orphaned success responses are silently dropped.

## No Defensive Wrapping

Session method calls from notification dispatch are not wrapped in `pcall`. Internal errors propagate and surface as bugs. These are not user-provided extension points; they are internal wiring.

## Connection Chain

`create_client` → `Client.new` (spawn + initialize) → errors propagate as Lua errors. The calling coop task receives the error. `plugin:create_client` re-raises, `plugin:session` propagates to the spawning coop task.
