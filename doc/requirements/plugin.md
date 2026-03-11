# ACP Neovim Plugin — Requirements

## Overview

A Neovim plugin implementing the Agent Client Protocol (ACP) v1. The plugin spawns an ACP-compatible agent over stdio, renders the conversation as markdown in a single buffer, and exposes hooks for statusline integration, system notifications, and mode switching.

The plugin is batteries-included: default window creation, notifications via `vim.notify`, and a statusline function all work out of the box. Every one of these is a composable primitive — users can override `create_window`, swap the notification routing, or build their own statusline from the exposed API. No terminal emulation, no window layout opinions beyond the defaults.

Every feature is exposed both as a `:Symbiont*` command and a corresponding `require("symbiont").*` Lua function. Commands are thin wrappers around the Lua API.

## Config

```lua
require("symbiont").setup({
  cmd           = "claude",
  args          = { "--acp" },
  env           = {},                          -- optional env vars
  create_window = function() ... return win end,
  create_plan_window = function() ... return win end,
  notification_handler = function(level, msg, kind) return "notify" end,
})
```

**`create_window`** — Must return a window handle; the plugin attaches its buffer to it. Defaults to a vertical split to the right of equal width. Override to use floats, tabs, or any custom layout.

**`create_plan_window`** — Must return a window handle. Defaults to a horizontal split below.

**`notification_handler`** — Called for every agent notification. Receives `(level, msg, kind)`. Returns one of:
- `"ignore"` — discard
- `"notify"` — `vim.notify(message, level)`
- `"system"` — system notification via `notify-send`

Default: returns `"notify"` for all events.

## Commands

| Command                    | Action                                                       |
|----------------------------|--------------------------------------------------------------|
| `:Symbiont`                | Start agent or focus/reopen window                           |
| `:Symbiont switch`         | Switch session (picker if >2, direct swap if 2)             |
| `:Symbiont new`            | Force a fresh session                                        |
| `:Symbiont stop`           | Kill agent, destroy buffer                                   |
| `:Symbiont cancel`         | Send `session/cancel` notification                           |
| `:[range]Symbiont submit {text}` | Send prompt (context-dependent, see below)                   |
| `:[range]Symbiont append`        | Attach current file/selection to prompt as resource link     |
| `:SymbiontMode [id]`       | Get or set agent mode (picker if no arg)                     |
| `:SymbiontPlan`            | Toggle dedicated plan buffer                                 |

### Symbiont

There is no `:Symbiont start` command. Toggle subsumes it.

1. Agent not started → start agent, pick/create session, create window via user fn, attach buffer.
   After `initialize`, the plugin sends `session/list` scoped to cwd:
   - Zero sessions → `session/new`.
   - One session → auto-load it via `session/load`.
   - Multiple sessions → auto-load the most recent session.
2. Agent running, symbiont buffer visible in some window → focus that window.
3. Agent running, symbiont buffer not visible → call `create_window` again, re-attach buffer.

### Symbiont switch

`:Symbiont switch`

Switches to a different session within the current cwd. Requires a running agent.

- **Two sessions**: directly switches to the other session via `session/load`.
- **More than two sessions**: opens `vim.ui.select` with session titles and timestamps; the user picks one to load.

If only one session exists, notifies "no other sessions" and does nothing.

### Symbiont new

Forces a new session regardless of existing ones. Kills the current agent if running, starts a fresh agent with `session/new`, creates the window, attaches the buffer.

### Symbiont stop

Kills the agent and destroys the buffer.

### Symbiont cancel

Sends `session/cancel` notification to the agent.

### Symbiont submit

Context-dependent behavior based on which buffer the command is invoked from.

**From conversation buffer** (`<CR>` normal, `<C-CR>` insert):

Sends the draft message content to the agent. The draft message is the last user `MessageBlock` in the conversation and contains `ResourceLink` blocks from prior appends plus `TextContent` from user typing. Open buffer `resource_link` blocks are added at submit time. The conversation buffer itself is NOT included as context. The prompt area is NOT cleared after sending — the user can re-submit or edit.

**From any other buffer** (`:[range]Symbiont submit {text}`, command only):

Content is added to the prompt area (as the draft message), then sent immediately:

- Without range: sends full current buffer as `EmbeddedResource` (includes unsaved changes).
- With range: sends selected lines as `EmbeddedResource`.
- `{text}` argument sent as `TextContent` if provided.
- Open buffer `resource_link` blocks are added at submit time.

### Symbiont append

`:[range]Symbiont append`

Adds the current file (or selected range) as a `ResourceLink` content block at the start of the user's draft message in the prompt area. Multiple appends accumulate — each adds another `ResourceLink`. Does not open or focus the symbiont window. If the agent is not running, auto-starts it (same session continuity flow as `:Symbiont`).

- Without range: `uri` is `file:///absolute/path/to/file.lua`.
- With range: `uri` includes a fragment, e.g. `file:///absolute/path/to/file.lua#L10-L25`.
- `name`: filename. `title`: `filename` or `filename:10-25` for ranges.

Rendered in the prompt area as `[{title}]({uri})` (per existing `ContentBlock` rendering spec). The user deletes the rendered line to remove the attachment. The agent reads file content from disk when it processes the link.

The user stays in their current window. Use `:Symbiont` to see the response or review the populated prompt.

### SymbiontMode [id]

- `:SymbiontMode` with no argument — opens `vim.ui.select` with available modes.
- `:SymbiontMode architect` — bypasses the picker and sends `session/set_mode` directly.

Tab completion pulls from `availableModes` returned in `session/new` / `session/load` responses. The actual mode change notification comes back via `session/update` with `sessionUpdate = "current_mode_update"`, which triggers the `AcpModeChanged` autocmd. The agent can also switch modes autonomously (e.g. via a `switch_mode` tool call), and the plugin picks that up the same way.

Programmatic: `require("symbiont").set_mode("architect")`, `require("symbiont").get_mode()`, `require("symbiont").get_modes()`, `require("symbiont").statusline()`.

`statusline()` returns a string for statusline integration. Empty string when the agent is not running, otherwise the current mode name.

### SymbiontPlan

Toggles a dedicated read-only plan buffer (`filetype=symbiont-plan`, `buftype=nofile`). Only works when an agent is running; otherwise notifies "no active session". The buffer updates live as `plan` session updates arrive.

Plans are read-only. The agent sends plan snapshots via `session/update` with `sessionUpdate = "plan"`. Each snapshot is a complete replacement — the plugin renders the latest set of `PlanEntry` items as a checkbox list with status and priority. There is no client-side plan editing; the agent owns the plan lifecycle. Plan blocks are **not** rendered inline in the conversation buffer.

Programmatic: `require("symbiont").toggle_plan()`.

## Notifications & Autocmds

The plugin fires one `User` autocmd and listens to one built-in autocmd:

### DirChanged

The plugin listens to the `DirChanged` autocmd. On cwd change, it auto-stops the current agent and destroys the buffer. The next `SymbiontToggle` starts fresh in the new cwd with the normal session continuity flow. Session data is preserved on the agent side, so resuming in the old cwd later picks up where it left off.

### AcpModeChanged

Fired when the agent's mode changes. `vim.v.event.data` contains:

| Field     | Type        | Values |
|-----------|-------------|--------|
| `mode_id` | string\|nil | mode identifier, nil on shutdown |

Modes are agent-defined and advertised dynamically.

## Structural Requirements

### Session

Internally the session is an ordered array of blocks with a side-index for ID-based lookup:

```
blocks[]    ordered by insertion — determines render order
```

Block kinds: `message`, `tool_call`, `plan`, `mode`.

Messages from the same role arriving consecutively are merged (content appended to last block). Tool call updates patch in-place via index lookup — `content` and `locations` replace the existing arrays, `status`/`title`/`kind` replace scalars (see [ToolCallUpdate](../research/acp-messages.md#toolcallupdate)).

Loaded sessions replay their history into the internal block model so the full conversation renders immediately.

### Buffer

Single buffer, filetype `symbiont`, buftype `nofile`.

#### Filetype and Folding

The plugin registers a custom `symbiont` filetype and injects the markdown treesitter parser for it. Fold levels are computed from treesitter nodes.

#### Rendering

See [rendering.md](rendering.md).

The prompt area is the last user message block. `InsertEnter` autocmd prevents edits above it.

#### Permissions

User checks one option (types `x` inside `[ ]`), presses `<CR>` in normal mode. Plugin parses which checkbox is checked, responds to the agent's JSON-RPC request, removes the permission block from the conversation, and resumes normal flow.

The ACP spec defines four permission option kinds: `allow_once`, `allow_always`, `reject_once`, `reject_always`. The plugin renders whatever options the agent provides in its `PermissionOption` array.

This is a synchronous blocking flow from the agent's perspective — the JSON-RPC request ID is held until the user responds.

## Not In Scope

- Terminal emulation / pty handling
- Multiple concurrent agents within a single Neovim instance
- MCP server configuration passthrough
- Session persistence beyond what the agent provides
