# Neovim Lua Plugin Reference

Covers the Neovim API surface relevant to building a Lua plugin that spawns processes, manages buffers, renders with extmarks, and communicates over JSON-RPC.

## Plugin Structure

Standard directory layout:

```
plugin/symbiont.lua       loaded once on startup (commands, autocmds)
lua/symbiont/init.lua     require("symbiont") entry point
lua/symbiont/config.lua   defaults + merge logic
lua/symbiont/session.lua  internal module
lua/symbiont/health.lua   :checkhealth symbiont
ftplugin/symbiont.lua     buffer-local settings when filetype is set
doc/symbiont.txt          vimdoc help file
```

`plugin/` files execute once at startup. `lua/` files load on first `require()`. `ftplugin/` files execute each time a buffer's filetype is set.

`require()` caches in `package.loaded`. A second `require("symbiont")` returns the cached table. During development, `package.loaded["symbiont"] = nil` forces reload.

Lazy loading: defer heavy initialization to the first command invocation or `setup()` call rather than `plugin/` load time.

## Configuration

Convention: a single `setup(opts)` entry point merges user config over defaults.

```lua
local M = {}
local config = {}

local defaults = {
  cmd = "claude",
  args = { "--acp" },
  env = {},
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})
  vim.validate("cmd", config.cmd, "string")
  vim.validate("args", config.args, "table")
  vim.validate("create_window", config.create_window, "function", true)
end

function M.get_config()
  return config
end

return M
```

`vim.tbl_deep_extend("force", defaults, opts)` deep-merges tables; "force" means `opts` wins on conflict. The fourth argument to `vim.validate` marks the field as optional.

`vim.g.symbiont_*` for user-facing global variables (less common with `setup()` pattern).

## Commands

### nvim_create_user_command

```lua
vim.api.nvim_create_user_command("Symbiont", function(ctx)
  -- ctx fields: args, fargs, bang, line1, line2, range, count, mods, smods
end, {
  nargs = "?",    -- "0", "1", "?", "*", "+"
  bang = false,
  range = false,  -- true, "%", or a number
  complete = function(arg_lead, cmd_line, cursor_pos)
    return vim.tbl_filter(function(s)
      return s:find(arg_lead, 1, true) == 1
    end, { "new", "stop", "cancel", "submit", "append" })
  end,
  desc = "Symbiont: toggle or subcommand",
})
```

| ctx field | Type | Description |
|---|---|---|
| `args` | string | raw argument string |
| `fargs` | string[] | split arguments |
| `bang` | boolean | `!` used |
| `line1` | integer | start line (range) |
| `line2` | integer | end line (range) |
| `range` | integer | 0=no range, 1=one line, 2=two lines |
| `mods` | string | command modifiers string |
| `smods` | table | structured modifiers (`vertical`, `silent`, `tab`, etc.) |

Subcommand dispatch pattern:

```lua
local subcommands = {
  new = function(ctx) ... end,
  stop = function(ctx) ... end,
}

vim.api.nvim_create_user_command("Symbiont", function(ctx)
  local sub = ctx.fargs[1]
  if sub and subcommands[sub] then
    subcommands[sub](ctx)
  else
    M.toggle()
  end
end, { ... })
```

Range commands (visual selection):

```lua
vim.api.nvim_create_user_command("SymbiontAppend", function(ctx)
  local lines = vim.api.nvim_buf_get_lines(0, ctx.line1 - 1, ctx.line2, false)
  append_with_selection(ctx.args, lines)
end, {
  nargs = "*",
  range = true,
  desc = "Append text, optionally with visual selection",
})
```

When called from visual mode (`:'<,'>SymbiontAppend`), `ctx.line1`/`ctx.line2` contain the selection boundaries. `ctx.range` is `2` for a two-line range, `0` when no range was given.

Buffer-local commands: `vim.api.nvim_buf_create_user_command(buf, name, fn, opts)`. Automatically removed when the buffer is deleted.

## Autocommands

### nvim_create_augroup / nvim_create_autocmd

```lua
local group = vim.api.nvim_create_augroup("Symbiont", { clear = true })

vim.api.nvim_create_autocmd("BufLeave", {
  group = group,
  callback = function(ev)
    -- ev fields: id, event, group, match, buf, file, data
    track_last_buffer(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("DirChanged", {
  group = group,
  pattern = "global",
  callback = function(ev)
    stop_agent()
  end,
})
```

| Option | Type | Description |
|---|---|---|
| `group` | string\|integer | augroup name or id |
| `pattern` | string\|string[] | file pattern or event-specific filter |
| `buffer` | integer | restrict to specific buffer |
| `callback` | function | receives event table, return `true` to delete |
| `once` | boolean | fire only once then auto-delete |
| `nested` | boolean | allow triggering other autocmds |
| `desc` | string | description for `:autocmd` listing |

Buffer-scoped autocmd: set `buffer = bufnr` instead of `pattern`. Automatically cleaned up when the buffer is deleted.

### Firing User events

```lua
vim.api.nvim_exec_autocmds("User", {
  pattern = "AcpModeChanged",
  data = { mode_id = "architect" },
})
```

Listeners receive the data in `ev.data`.

### Common events reference

| Event | Fires when |
|---|---|
| `BufEnter` / `BufLeave` | cursor enters/leaves buffer |
| `WinEnter` / `WinLeave` | cursor enters/leaves window |
| `InsertEnter` / `InsertLeave` | insert mode toggled |
| `TextChanged` / `TextChangedI` | buffer text modified (normal / insert) |
| `BufDelete` / `BufWipeout` | buffer deleted / wiped |
| `DirChanged` | cwd changed |
| `FileType` | filetype set on buffer |
| `User` | custom events via `nvim_exec_autocmds` |

## Buffer Management

### Creating buffers

```lua
local buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
```

| Option | Value | Effect |
|---|---|---|
| `buftype` | `"nofile"` | no file association, no swap |
| `bufhidden` | `"wipe"` | wipe buffer when hidden |
| `modifiable` | `false` | prevent user edits |
| `filetype` | `"symbiont"` | triggers ftplugin, treesitter |
| `swapfile` | `false` | no swap file |

```lua
vim.bo[buf].buftype = "nofile"
vim.bo[buf].bufhidden = "wipe"
vim.bo[buf].swapfile = false
vim.bo[buf].filetype = "symbiont"
```

### Setting buffer content

`nvim_buf_set_lines` replaces whole lines. `nvim_buf_set_text` replaces a character range.

```lua
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

vim.api.nvim_buf_set_text(buf, start_row, start_col, end_row, end_col, replacement_lines)
```

For streaming append (adding text to the last line):

```lua
local last = vim.api.nvim_buf_line_count(buf) - 1
local last_line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
vim.api.nvim_buf_set_text(buf, last, #last_line, last, #last_line, { chunk })
```

When `modifiable = false`, temporarily enable before writing:

```lua
vim.bo[buf].modifiable = true
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.bo[buf].modifiable = false
```

### Buffer validity and window lookup

```lua
vim.api.nvim_buf_is_valid(buf)          -- buffer still exists
vim.api.nvim_buf_is_loaded(buf)         -- buffer loaded in memory
vim.fn.win_findbuf(buf)                 -- list of window IDs displaying this buffer
vim.api.nvim_list_wins()                -- all window IDs
vim.api.nvim_win_get_buf(win)           -- buffer displayed in window
vim.api.nvim_win_is_valid(win)          -- window still exists
```

Re-attach pattern: find if a buffer is already visible, otherwise create a new window for it:

```lua
local wins = vim.fn.win_findbuf(buf)
if #wins > 0 then
  vim.api.nvim_set_current_win(wins[1])
else
  local win = create_window()
  vim.api.nvim_win_set_buf(win, buf)
end
```

### Buffer-local keymaps

```lua
vim.keymap.set("n", "<CR>", function()
  submit_prompt()
end, { buffer = buf, desc = "Submit prompt" })
```

### Buffer-local variables

```lua
vim.b[buf].symbiont_session_id = session_id
local sid = vim.b[buf].symbiont_session_id
```

## Extmarks

### Namespaces

```lua
local ns = vim.api.nvim_create_namespace("symbiont")
local ns_sep = vim.api.nvim_create_namespace("symbiont_separator")
```

Namespaces isolate extmarks so they can be cleared independently.

### nvim_buf_set_extmark

```lua
local id = vim.api.nvim_buf_set_extmark(buf, ns, row, col, opts)
```

| Option | Type | Description |
|---|---|---|
| `id` | integer | reuse existing extmark id (update in place) |
| `hl_group` | string | highlight group for the text range |
| `end_row` | integer | end of highlighted region |
| `end_col` | integer | end column |
| `virt_text` | `{text, hl}[]` | virtual text chunks |
| `virt_text_pos` | string | `"eol"`, `"overlay"`, `"inline"`, `"right_align"` |
| `virt_lines` | `{{text, hl}[]}[]` | virtual lines below the extmark line |
| `virt_lines_above` | boolean | place virtual lines above instead |
| `sign_text` | string | sign column text (max 2 chars) |
| `line_hl_group` | string | highlight entire line |
| `conceal` | string | conceal character (empty string to hide) |
| `priority` | integer | rendering priority (default 4096) |
| `right_gravity` | boolean | extmark moves with text insertions (default true) |

Virtual text positions:

| Position | Behavior |
|---|---|
| `"eol"` | after end of line |
| `"overlay"` | replaces text at the extmark position |
| `"inline"` | inserted between characters, shifts text right |
| `"right_align"` | right-aligned to window edge |

### Querying and clearing

```lua
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, {start_row, 0}, {end_row, -1}, {
  details = true,
})
-- returns: { {id, row, col, details}, ... }

vim.api.nvim_buf_del_extmark(buf, ns, id)

vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) -- clear all in namespace
```

### Range tracking pattern

Set an extmark at the start of a block. On update, query its current position to find where the block has shifted. Combined with `right_gravity = false` on the end marker, the range adjusts as surrounding content changes.

```lua
local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, start_row, 0, {
  right_gravity = false,
})
-- later:
local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark_id, {})
local current_row = pos[1]
```

## Window Management

### Splits

```lua
vim.cmd("vsplit")
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, buf)
```

### Floats

```lua
local win = vim.api.nvim_open_win(buf, true, {
  relative = "editor",
  width = 80,
  height = 24,
  row = 2,
  col = 10,
  border = "rounded",  -- "none", "single", "double", "rounded", "solid", "shadow"
  title = "Symbiont",
  title_pos = "center",
  style = "minimal",   -- no number, signcolumn, foldcolumn
  zindex = 50,
})
```

`vim.api.nvim_win_set_config(win, opts)` updates an existing window's config (convert split to float or resize).

### Window-local options

```lua
vim.wo[win].wrap = true
vim.wo[win].number = false
vim.wo[win].signcolumn = "no"
vim.wo[win].foldmethod = "expr"
vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo[win].conceallevel = 2
vim.wo[win].winfixheight = true
vim.wo[win].scrolloff = 0
vim.wo[win].cursorline = true
```

### nvim_win_call

Execute a function in the context of a specific window (sets current window temporarily):

```lua
vim.api.nvim_win_call(win, function()
  vim.cmd("normal! G0zb")
end)
```

## Process Spawning

Three approaches, from simplest to most control.

### vim.system

Preferred for simple async/sync process execution.

```lua
local obj = vim.system(
  { "claude", "--acp" },
  {
    stdin = true,       -- keep stdin open (pipe)
    stdout = function(err, data)
      if data then handle_stdout(data) end
    end,
    stderr = function(err, data)
      if data then handle_stderr(data) end
    end,
    env = vim.tbl_extend("force", vim.fn.environ(), { CLAUDE_TOKEN = "..." }),
    cwd = vim.fn.getcwd(),
  }
)

obj:write(payload)    -- write to stdin
obj:write(nil)        -- close stdin (send EOF)
obj:kill(signal)      -- send signal (default SIGTERM)
obj:wait(timeout)     -- block until exit, returns SystemCompleted
obj.pid               -- process ID
```

`SystemCompleted` (from `:wait()` or sync mode): `{ code, signal, stdout, stderr }`.

`env` **replaces** the inherited environment entirely. To extend instead, merge with `vim.fn.environ()` first: `vim.tbl_extend("force", vim.fn.environ(), user_env)`.

Sync mode: omit callbacks, call `:wait()` or pass no `on_exit`.

### vim.fn.jobstart

Lower level, callback-based. Data arrives as string arrays with a trailing empty string on complete lines.

```lua
local job_id = vim.fn.jobstart({ "claude", "--acp" }, {
  on_stdout = function(id, data, event)
    -- data: string[] with trailing "" if line complete
    for _, line in ipairs(data) do
      if line ~= "" then handle_line(line) end
    end
  end,
  on_stderr = function(id, data, event) ... end,
  on_exit = function(id, code, event) ... end,
  stdin = "pipe",
})

vim.fn.chansend(job_id, payload .. "\n")
vim.fn.chanclose(job_id, "stdin")
vim.fn.jobstop(job_id)
```

Data format quirk: Neovim splits on `\n` and includes a trailing empty string when the chunk ends with a newline. Partial lines must be buffered across callbacks.

### vim.uv.spawn

Maximum control via libuv directly. Requires manual pipe management and `vim.schedule` for any Neovim API calls.

```lua
local stdin = vim.uv.new_pipe()
local stdout = vim.uv.new_pipe()
local stderr = vim.uv.new_pipe()

local handle, pid = vim.uv.spawn("claude", {
  args = { "--acp" },
  stdio = { stdin, stdout, stderr },
  cwd = vim.fn.getcwd(),
}, function(code, signal)
  -- on exit (libuv thread — must vim.schedule for API calls)
  vim.schedule(function()
    handle_exit(code, signal)
  end)
end)

stdout:read_start(function(err, data)
  if data then
    vim.schedule(function()
      handle_stdout(data)
    end)
  end
end)

stdin:write(payload)
stdin:shutdown()  -- close write end
handle:kill(signal)
```

### When to use each

| Approach | Use case |
|---|---|
| `vim.system` | Long-running process with stdin/stdout streaming, simplest API |
| `vim.fn.jobstart` | Legacy compatibility, callback-per-event model |
| `vim.uv.spawn` | Need raw pipe control, custom signal handling, timer integration |

## Event Loop

### vim.schedule

Defers a function to the main Neovim event loop. Required when calling Neovim API functions from libuv callbacks (`vim.uv.*`, `vim.system` stdout/stderr callbacks).

```lua
stdout:read_start(function(err, data)
  -- WRONG: vim.api.nvim_buf_set_lines(...) -- crashes
  -- RIGHT:
  vim.schedule(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, parse(data))
  end)
end)
```

`vim.schedule_wrap(fn)` returns a new function that wraps `fn` in `vim.schedule`:

```lua
local safe_handler = vim.schedule_wrap(function(data)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, parse(data))
end)
```

### Timers

`vim.uv.new_timer()` for throttled/debounced rendering:

```lua
local timer = vim.uv.new_timer()
local pending = false

local function schedule_render()
  if pending then return end
  pending = true
  timer:start(50, 0, vim.schedule_wrap(function()
    pending = false
    render()
  end))
end
```

`timer:start(timeout_ms, repeat_ms, callback)` — `repeat_ms = 0` for one-shot.

`vim.wait(timeout, condition, interval)` polls synchronously (blocks the editor):

```lua
vim.wait(5000, function()
  return result ~= nil
end, 50)
```

## JSON-RPC over stdio

ACP uses JSON-RPC 2.0 with Content-Length framing (same as LSP).

### Framing

```
Content-Length: 42\r\n
\r\n
{"jsonrpc":"2.0","method":"session/update","params":{...}}
```

### Message types

**Request** (expects response): `{ jsonrpc: "2.0", id: number|string, method: string, params?: object }`

**Response**: `{ jsonrpc: "2.0", id: number|string, result?: object, error?: { code, message, data? } }`

**Notification** (no response): `{ jsonrpc: "2.0", method: string, params?: object }`

### Parsing incoming data

Buffer chunks, extract complete messages by Content-Length:

```lua
local buffer = ""

local function on_data(chunk)
  buffer = buffer .. chunk
  while true do
    local header_end = buffer:find("\r\n\r\n", 1, true)
    if not header_end then break end
    local header = buffer:sub(1, header_end - 1)
    local len = tonumber(header:match("Content%-Length:%s*(%d+)"))
    if not len then break end
    local body_start = header_end + 4
    if #buffer < body_start + len - 1 then break end
    local body = buffer:sub(body_start, body_start + len - 1)
    buffer = buffer:sub(body_start + len)
    local msg = vim.json.decode(body)
    dispatch(msg)
  end
end
```

### Sending messages

```lua
local request_id = 0

local function send(obj)
  local body = vim.json.encode(obj)
  local frame = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
  process:write(frame)
end

local function request(method, params, callback)
  request_id = request_id + 1
  local id = request_id
  pending_requests[id] = callback
  send({ jsonrpc = "2.0", id = id, method = method, params = params })
end

local function notify(method, params)
  send({ jsonrpc = "2.0", method = method, params = params })
end
```

### ID correlation

Store pending request callbacks keyed by ID. When a response arrives, look up and invoke the callback:

```lua
local function dispatch(msg)
  if msg.id and pending_requests[msg.id] then
    local cb = pending_requests[msg.id]
    pending_requests[msg.id] = nil
    cb(msg.error, msg.result)
  elseif msg.method then
    handle_notification(msg.method, msg.params)
  end
end
```

### JSON encoding

```lua
vim.json.encode(value)  -- Lua → JSON string
vim.json.decode(str)    -- JSON string → Lua
```

JSON `null` maps to `vim.NIL` (a special userdata sentinel). To convert `null` to Lua `nil` instead:

```lua
vim.json.decode(str, { luanil = { object = true, array = true } })
```

Reference: Neovim's own `vim.lsp.rpc` module implements the same Content-Length framing and ID correlation for LSP.

## Treesitter Integration

### Custom filetype detection

```lua
vim.filetype.add({
  extension = { symbiont = "symbiont" },
  -- or pattern-based:
  pattern = { [".*%.symbiont"] = "symbiont" },
})
```

### Reusing an existing parser

Map a custom filetype to an existing parser (e.g. markdown):

```lua
vim.treesitter.language.register("markdown", "symbiont")
```

After this, buffers with `filetype=symbiont` use the markdown parser for highlighting, folds, and queries.

### Fold integration

Set the window to use treesitter folds:

```lua
vim.wo[win].foldmethod = "expr"
vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
```

Fold levels are derived from the treesitter parse tree.

### Custom fold queries

Place a query file at `queries/symbiont/folds.scm`. Nodes captured as `@fold` become foldable regions:

```scm
; queries/symbiont/folds.scm
; fold heading sections (atx_heading through next sibling)
(section) @fold
```

For more targeted folds (e.g. only H4 tool-call blocks), match specific heading levels:

```scm
(section
  (atx_heading
    (atx_h4_marker)) @fold)
```

The `@fold` capture tells `vim.treesitter.foldexpr()` to assign fold levels to those nodes. Queries use the S-expression syntax from tree-sitter — node types come from the language grammar (for markdown: `section`, `atx_heading`, `atx_h4_marker`, `fenced_code_block`, etc.).

To override fold behavior entirely with a Lua function instead of queries:

```lua
vim.wo[win].foldmethod = "expr"
vim.wo[win].foldexpr = "v:lua.require('symbiont.fold').foldexpr(v:lnum)"
```

## UI Primitives

### vim.ui.select

```lua
vim.ui.select(items, {
  prompt = "Select session:",
  format_item = function(item)
    return item.title .. " (" .. item.updatedAt .. ")"
  end,
}, function(selected, idx)
  if selected then
    load_session(selected.sessionId)
  end
end)
```

Override: plugins like dressing.nvim and snacks.nvim replace `vim.ui.select` with floating windows or telescope pickers. The API contract stays the same.

### vim.ui.input

```lua
vim.ui.input({
  prompt = "Rejection reason: ",
  default = "",
}, function(input)
  if input then respond(input) end
end)
```

### vim.notify

```lua
vim.notify("Agent started", vim.log.levels.INFO)
vim.notify("Connection failed", vim.log.levels.ERROR)
```

Levels: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`. Override: plugins like nvim-notify and snacks.nvim replace `vim.notify` with richer UIs.

## Health Checks

Module at `lua/symbiont/health.lua`:

```lua
local M = {}

function M.check()
  vim.health.start("symbiont")

  if vim.fn.executable("claude") == 1 then
    vim.health.ok("claude binary found")
  else
    vim.health.error("claude binary not found", { "Install claude CLI" })
  end

  local has_ts = pcall(vim.treesitter.language.inspect, "markdown")
  if has_ts then
    vim.health.ok("markdown treesitter parser installed")
  else
    vim.health.warn("markdown treesitter parser not found", { ":TSInstall markdown" })
  end

  vim.health.info("plugin version: 0.1.0")
end

return M
```

Run with `:checkhealth symbiont`.

Functions: `vim.health.start(name)`, `vim.health.ok(msg)`, `vim.health.warn(msg, advice?)`, `vim.health.error(msg, advice?)`, `vim.health.info(msg)`.

## Error Handling

### pcall / xpcall

```lua
local ok, result = pcall(vim.json.decode, raw)
if not ok then
  vim.notify("Invalid JSON: " .. result, vim.log.levels.ERROR)
  return
end
```

`xpcall` adds a custom error handler (useful for stack traces):

```lua
local ok, result = xpcall(risky_fn, function(err)
  return debug.traceback(err, 2)
end)
```

### Optional dependency pattern

```lua
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
if has_devicons then
  local icon = devicons.get_icon(filename)
end
```

## Testing

### plenary.nvim

Busted-style syntax, runs inside a headless Neovim instance. Tests have full access to the Neovim API.

```lua
-- tests/session_spec.lua
describe("session", function()
  it("creates a block on update", function()
    local session = require("symbiont.session").new()
    session:handle_update({ sessionUpdate = "agent_message_chunk", ... })
    assert.equals(1, #session.blocks)
  end)
end)
```

Run: `nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"`.

### mini.test

Spawns a child Neovim process. Supports screenshot comparison for UI testing.

```lua
local child = MiniTest.new_child_neovim()

T["render"] = function()
  child.restart({ "-u", "tests/minimal_init.lua" })
  child.lua("require('symbiont').setup({})")
  child.lua("require('symbiont').toggle()")
  child.expect_screenshot()
end
```

### busted + nlua

Standalone Lua testing without a Neovim instance. Useful for pure data logic (session model, JSON-RPC parsing) that doesn't depend on the Neovim API.

```sh
nlua -e "require('busted.runner')({ standalone = false })" -- tests/rpc_spec.lua
```

### Async test patterns

For testing async operations, `vim.wait` polls until a condition is met:

```lua
it("receives response", function()
  local done = false
  send_request(function() done = true end)
  vim.wait(5000, function() return done end, 50)
  assert.is_true(done)
end)
```
