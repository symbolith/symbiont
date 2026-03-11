# Module Interfaces

Function signatures for every module in the plugin. Dependency-leaf-first order: modules appear after all modules they depend on.

Types reference [Data Structures](data-structures.md) (internal types) and [ACP Messages](../research/acp-messages.md) (wire types) — not redefined here.

**Conventions**:
- Stateful modules use metatables with `Class.new()` constructors and `:method()` instance methods.
- Stateless modules use plain module tables with `M.function()` calls.
- All annotations use [LuaCATS](https://luals.github.io/wiki/annotations/) style.

## config

Stateless. Plugin configuration: defaults, user overrides, validation.

```lua
local config = require("symbiont.config")

---@param opts symbiont.Config? User overrides merged onto defaults. Validates after merge.
function config.setup(opts) end

---@return symbiont.Config
function config.get() end
```

`setup` is idempotent — second call re-merges from defaults. `get` returns the frozen merged table; callers must not mutate it.

## render

Stateless. Pure functions: data in, `string[]` out. No Neovim API calls, no side effects. Every function returns lines ready for `nvim_buf_set_lines`.

```lua
local render = require("symbiont.render")

---@param block symbiont.MessageBlock
---@return string[]
function render.message(block) end

---@param block symbiont.ToolCallBlock
---@return string[]
function render.tool_call(block) end

---@param blocks symbiont.Block[]
---@return string[]
function render.conversation(blocks) end

---@param entries PlanEntry[]
---@return string[]
function render.plan(entries) end

---@param tool_call ToolCallUpdate
---@param options PermissionOption[]
---@return string[]
function render.permission(tool_call, options) end

---@param content ContentBlock
---@return string[]
function render.content_block(content) end
```

`render.conversation` iterates `blocks` and dispatches to `render.message` / `render.tool_call` per block kind, concatenating results. `render.content_block` handles [ContentBlock](../research/acp-messages.md#contentblock) discriminated union dispatch (`text`, `image`, `resource_link`, `resource`).

## rpc

Stateful. JSON-RPC 2.0 transport over stdio. No knowledge of ACP semantics.

```lua
local Rpc = require("symbiont.rpc")

---@class symbiont.RpcCallbacks
---@field on_notification fun(method: string, params: table)
---@field on_request fun(method: string, params: table, respond: fun(result: table?, err: table?))
---@field on_error fun(err: string)
---@field on_exit fun(code: integer, signal: integer)

---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param cwd string
---@param callbacks symbiont.RpcCallbacks
---@return symbiont.Rpc
function Rpc.new(cmd, args, env, cwd, callbacks) end

---@param method string
---@param params table
---@param callback fun(err: table?, result: table?)
function Rpc:request(method, params, callback) end

---@param method string
---@param params table
function Rpc:notify(method, params) end

---@param id string|integer JSON-RPC request ID from an agent-initiated request
---@param result table?
---@param err table?
function Rpc:respond(id, result, err) end

---@return boolean
function Rpc:is_ready() end

function Rpc:shutdown() end
```

`Rpc.new` spawns the process via `vim.system`, begins reading stdout. All callbacks fire on `vim.schedule` so callers can use Neovim API directly.

`on_request` receives a `respond` closure bound to the request ID — the caller invokes it when ready (used for `session/request_permission`). `respond` is a convenience for cases where the caller holds the ID directly.

`shutdown` sends EOF on stdin, waits for process exit, then fires `on_exit`.

## acp

Stateless. ACP protocol semantics. Param builders return tables ready for `rpc:request` / `rpc:notify`. No knowledge of transport or session state.

```lua
local acp = require("symbiont.acp")

---@return table
function acp.initialize_params() end

---@param cwd string
---@return table
function acp.session_list_params(cwd) end

---@param cwd string
---@return table
function acp.session_new_params(cwd) end

---@param session_id string
---@param cwd string
---@return table
function acp.session_load_params(session_id, cwd) end

---@param session_id string
---@param prompt ContentBlock[]
---@return table
function acp.session_prompt_params(session_id, prompt) end

---@param session_id string
---@return table
function acp.session_cancel_params(session_id) end

---@param session_id string
---@param mode_id string
---@return table
function acp.session_set_mode_params(session_id, mode_id) end
```

```lua
---@class symbiont.DispatchedUpdate
---@field kind "user_message_chunk"|"agent_message_chunk"|"agent_thought_chunk"|"tool_call"|"tool_call_update"|"plan"|"current_mode_update"|"available_commands_update"|"config_option_update"
---@field data table snake_case-normalized payload

---@param update table Raw SessionUpdate from the wire
---@return symbiont.DispatchedUpdate
function acp.dispatch_update(update) end
```

```lua
---@param outcome "selected"|"cancelled"
---@param option_id string? Required when outcome is "selected"
---@return RequestPermissionOutcome
function acp.permission_outcome(outcome, option_id) end
```

```lua
acp.methods = {
  initialize = "initialize",
  session_list = "session/list",
  session_new = "session/new",
  session_load = "session/load",
  session_prompt = "session/prompt",
  session_cancel = "session/cancel",
  session_update = "session/update",
  session_set_mode = "session/set_mode",
  session_request_permission = "session/request_permission",
}
```

`session_list_params` always fetches the first page — the wire spec's optional `cursor` field is not used. `session_new_params` and `session_load_params` hard-code `mcpServers = {}` — MCP server passthrough is [out of scope](../requirements/plugin.md).

`dispatch_update` reads the `sessionUpdate` discriminator, converts camelCase payload fields to snake_case, and returns a tagged result. Callers switch on `kind`.

## conversation

Stateful. Ordered block storage with message merging and tool call patching.

```lua
local Conversation = require("symbiont.conversation")

---@return symbiont.Conversation
function Conversation.new() end

---@param role "user"|"assistant"|"thought"
---@param content ContentBlock
function Conversation:append_message(role, content) end

---@param tool_call ToolCall snake_case-normalized
function Conversation:add_tool_call(tool_call) end

---@param update ToolCallUpdate snake_case-normalized
function Conversation:update_tool_call(update) end

---@return symbiont.Block[]
function Conversation:get_blocks() end

function Conversation:clear() end
```

`append_message` merges into the last block when role matches (appends to `content` array). Otherwise appends a new [MessageBlock](data-structures.md). `add_tool_call` appends a new [ToolCallBlock](data-structures.md) and indexes it by `tool_call_id`. `update_tool_call` patches the indexed block in place — `content`/`locations` replace arrays, `status`/`title`/`tool_kind` replace scalars, absent fields unchanged.

## plan

Stateful. Plan entry state. Complete replacement on each update.

```lua
local Plan = require("symbiont.plan")

---@return symbiont.Plan
function Plan.new() end

---@param entries PlanEntry[]
function Plan:set(entries) end

---@return PlanEntry[]
function Plan:get() end

function Plan:clear() end
```

`set` replaces the entire entry list — no diffing, no merging.

## buffer

Stateful. Neovim buffer lifecycle for conversation and plan display. Depends on [config](#config) and [render](#render). Calls render internally — callers pass data, not pre-rendered lines.

```lua
local Buffer = require("symbiont.buffer")

---@param config symbiont.Config
---@return symbiont.Buffer
function Buffer.new(config) end

---@param blocks symbiont.Block[]
function Buffer:update_conversation(blocks) end

---@param block symbiont.ToolCallBlock
function Buffer:patch_tool_call(block) end

---@param entries PlanEntry[]
function Buffer:update_plan(entries) end

---@param tool_call ToolCallUpdate
---@param options PermissionOption[]
---@param on_respond fun(option_id: string)
function Buffer:show_permission(tool_call, options, on_respond) end

function Buffer:clear_permission() end

---@return ContentBlock[] Content blocks from the prompt area
function Buffer:read_prompt() end

---@param content string
function Buffer:write_prompt(content) end

function Buffer:show() end

---@return boolean
function Buffer:is_visible() end

function Buffer:toggle_plan() end

function Buffer:destroy() end

---@return integer
function Buffer:get_buf() end
```

`Buffer.new` creates the buffer (`buftype=nofile`, `filetype=symbiont`), sets up the read-only guard, keymaps, and prompt separator. Does not create a window — `show` calls `config.create_window` and attaches the buffer.

`update_conversation` re-renders all blocks via `render.conversation` and replaces buffer content above the prompt. `patch_tool_call` updates a single tool call in place using extmark ranges — avoids full re-render for streaming updates.

`show_permission` renders the permission block, installs a keymap for checkbox selection, and stores `on_respond` for invocation when the user presses `<CR>`. `clear_permission` removes the permission block and restores normal keymaps.

`read_prompt` parses the prompt area below the separator, extracting `ResourceLink` blocks from rendered markdown links and `TextContent` from plain text. `write_prompt` replaces the prompt area text content.

`toggle_plan` creates or destroys the plan buffer and window via `config.create_plan_window`.

## session

Stateful. Session lifecycle, mode tracking, notification routing, permission flow coordination. Depends on [config](#config), [rpc](#rpc), [acp](#acp), [conversation](#conversation), [plan](#plan), [buffer](#buffer).

```lua
local Session = require("symbiont.session")

---@param config symbiont.Config
---@return symbiont.Session
function Session.new(config) end

---@param callback fun(sessions: SessionInfo[])
function Session:list_sessions(callback) end

---@param session_id string
function Session:load(session_id) end

function Session:new_session() end

function Session:switch() end

function Session:stop() end

function Session:cancel() end

---@class symbiont.SubmitOpts
---@field text string?
---@field range { start: integer, finish: integer }?
---@field bufnr integer?

---@param opts symbiont.SubmitOpts?
function Session:submit(opts) end

---@class symbiont.AppendOpts
---@field range { start: integer, finish: integer }?
---@field bufnr integer?

---@param opts symbiont.AppendOpts?
function Session:append(opts) end

---@param mode_id string
function Session:set_mode(mode_id) end

---@return string?
function Session:get_mode() end

---@return SessionMode[]
function Session:get_modes() end

---@return string
function Session:statusline() end

function Session:toggle_plan() end

---@return boolean
function Session:is_active() end
```

`Session.new` performs full startup: spawns `Rpc`, sends `initialize`, runs session resolution (list → load or new), creates `Buffer`, and shows it. The constructor builds the RPC callback table pointing at its own methods for notification dispatch.

`switch` lists sessions scoped to cwd: one session does nothing, two sessions swaps directly, three or more opens `vim.ui.select`. Calls `load` on selection.

`load` sends `session/load`, clears conversation and plan state, replays the returned history into the block model.

`submit` reads the prompt from `buffer:read_prompt()`, builds `ContentBlock[]`, sends `session/prompt`. When called with opts (from a non-conversation buffer), writes content to the prompt area first, then submits. `append` adds a `ResourceLink` to the prompt area without submitting.

`cancel` sends `session/cancel`. If a permission request is pending, responds with `cancelled` outcome first.

`stop` calls `rpc:shutdown()`, then `buffer:destroy()`.

`statusline` returns empty string when not active, otherwise the current mode name.

## init

Stateless. Public API surface. Holds at most one `Session` reference. Delegates everything to session.

```lua
local M = require("symbiont")

---@param opts symbiont.Config?
function M.setup(opts) end

function M.toggle() end
function M.switch() end
function M.new() end
function M.stop() end
function M.cancel() end

---@param opts symbiont.SubmitOpts?
function M.submit(opts) end

---@param opts symbiont.AppendOpts?
function M.append(opts) end

---@param mode_id string
function M.set_mode(mode_id) end

---@return string?
function M.get_mode() end

---@return SessionMode[]
function M.get_modes() end

---@return string
function M.statusline() end

function M.toggle_plan() end
```

`setup` calls `config.setup(opts)` and registers commands/autocommands. Does not start the agent.

`toggle` implements the three-state logic: no session → `Session.new`, session with hidden buffer → `buffer:show`, session with visible buffer → focus window.

`new` kills any existing session (`session:stop()`), then creates a fresh `Session.new`.

`stop` calls `session:stop()`, clears the session reference.

All other functions forward to the current session. If no session exists, they auto-start one (same flow as `toggle`), except `statusline` which returns `""`.

## health

Stateless. `:checkhealth symbiont` integration.

```lua
local health = require("symbiont.health")

function health.check() end
```

Checks:
- Agent binary (`config.cmd`) exists on `$PATH`
- `symbiont` treesitter parser is installed
- Neovim version meets minimum requirement

## Design Decisions

1. **OOP for stateful, plain tables for stateless.** Modules with instance state (Rpc, Conversation, Plan, Buffer, Session) use metatables with constructors and instance methods. Modules that are pure functions or configuration (config, render, acp, health) use plain module tables. This matches the natural grain — no forced uniformity.

2. **render/buffer separation.** `render` is pure: data in, `string[]` out, no Neovim API. `buffer` calls render internally and writes lines to Neovim buffers. This separation enables testing render logic without a Neovim instance. Buffer methods are named `update_*`/`show_*` to avoid confusion with render functions.

3. **Session lifecycle.** `:Symbiont switch` reuses the existing RPC connection — sends `session/load` to change sessions. `:Symbiont new` kills the agent process and starts fresh. `init` holds at most one session reference; there is no multi-session state within the plugin.
