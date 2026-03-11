# Data Structures

Internal Lua types used by the plugin, grouped by owning module. ACP wire types are defined in [ACP Messages](../research/acp-messages.md) and referenced by link — not redefined here. Annotations use [LuaCATS](https://luals.github.io/wiki/annotations/) style.

## init

No stored state. Public API surface; delegates to `session`.

## config

```lua
---@class symbiont.Config
---@field cmd string
---@field args string[]
---@field env table<string, string>
---@field create_window fun(): integer
---@field create_plan_window fun(): integer
---@field notification_handler fun(level: integer, msg: string, kind: string): "ignore"|"notify"|"system"
```

## session

```lua
---@class symbiont.AgentState
---@field current_mode_id string?
---@field available_modes SessionMode[]
---@field available_commands AvailableCommand[]
---@field config_options SessionConfigOption[]
---@field agent_capabilities AgentCapabilities?
```

[SessionMode](../research/acp-messages.md#sessionmode), [AvailableCommand](../research/acp-messages.md#availablecommand), [SessionConfigOption](../research/acp-messages.md#sessionconfigoption), and [AgentCapabilities](../research/acp-messages.md#agentcapabilities) are ACP wire types stored as received.

```lua
---@class symbiont.Session
---@field session_id string
---@field cwd string
---@field title string?
---@field rpc symbiont.Rpc
---@field conversation symbiont.Conversation
---@field plan symbiont.Plan
---@field buffer symbiont.Buffer
---@field agent_state symbiont.AgentState
---@field permission symbiont.PermissionState?
```

```lua
---@class symbiont.PermissionState
---@field request_id string|integer
---@field tool_call ToolCallUpdate
---@field options PermissionOption[]
```

Transient UI state, not part of conversation history. `request_id` is the JSON-RPC ID held until the user responds.

[ToolCallUpdate](../research/acp-messages.md#toolcallupdate), [PermissionOption](../research/acp-messages.md#permissionoption)

## rpc

```lua
---@class symbiont.Rpc
---@field handle vim.SystemObj
---@field pending table<integer, symbiont.PendingRequest>
---@field buf string
---@field next_id integer
---@field state "connecting"|"ready"|"closed"
```

`buf` accumulates raw bytes for Content-Length header parsing. `pending` maps request IDs to their callbacks.

```lua
---@class symbiont.PendingRequest
---@field callback fun(err: table?, result: table?)
---@field method string
```

## acp

No stored state. Constant tables and pure builder functions.

## conversation

```lua
---@class symbiont.Conversation
---@field blocks symbiont.Block[]
---@field tool_call_index table<string, symbiont.ToolCallBlock>
```

```lua
---@alias symbiont.Block symbiont.MessageBlock|symbiont.ToolCallBlock
```

```lua
---@class symbiont.MessageBlock
---@field kind "message"
---@field role "user"|"assistant"|"thought"
---@field content ContentBlock[]
```

```lua
---@class symbiont.ToolCallBlock
---@field kind "tool_call"
---@field tool_call_id string
---@field title string
---@field tool_kind ToolKind?
---@field status ToolCallStatus?
---@field content ToolCallContent[]?
---@field locations ToolCallLocation[]?
---@field raw_input table?
---@field raw_output table?
```

[ContentBlock](../research/acp-messages.md#contentblock), [ToolKind](../research/acp-messages.md#toolkind), [ToolCallStatus](../research/acp-messages.md#toolcallstatus), [ToolCallContent](../research/acp-messages.md#toolcallcontent), [ToolCallLocation](../research/acp-messages.md#toolcalllocation)

### Invariants

- **Insertion order**: `blocks` is append-only; order determines render order.
- **Message merging**: consecutive messages with the same `role` merge — new content blocks append to the existing message's `content` array.
- **Tool call patching**: updates match by `tool_call_id` via `tool_call_index`. `content` and `locations` replace existing arrays. `status`, `title`, `tool_kind` replace scalars. Absent fields remain unchanged.
- **Role mapping**: `user_message_chunk` → `"user"`, `agent_message_chunk` → `"assistant"`, `agent_thought_chunk` → `"thought"`. `tool_call` and `tool_call_update` produce `ToolCallBlock` entries.
- **snake_case**: wire-format camelCase fields (`toolCallId`, `rawInput`, etc.) are converted to snake_case on ingestion.

## plan

```lua
---@class symbiont.Plan
---@field entries PlanEntry[]
```

Complete replacement on each update. Rendered in a separate plan buffer, not inline in the conversation.

[PlanEntry](../research/acp-messages.md#planentry)

## render

No data structures. Pure functions from conversation/plan data to markdown lines.

## buffer

```lua
---@class symbiont.Buffer
---@field buf integer
---@field plan_buf integer?
---@field prompt_start_line_number integer
---@field tool_call_extmarks table<string, symbiont.ExtmarkRange>
```

`buf` is the conversation buffer handle. `plan_buf` is the optional plan buffer handle. `prompt_start_line_number` is the boundary between read-only content and the prompt area. `tool_call_extmarks` maps `tool_call_id` to extmark ranges for in-place patching.

```lua
---@class symbiont.ExtmarkRange
---@field start_id integer
---@field end_id integer
```

Extmark IDs, not line numbers — positions track through buffer mutations.

## health

No data structures.
