## Prior Art

How other Neovim plugins render each block type. Plugins: **agentic.nvim** (ACP-only, 5 nofile buffers), **codecompanion.nvim** (single nofile buffer, treesitter markdown), **avante.nvim** (NUI splits, requires render-markdown.nvim), **CopilotChat.nvim** (single nofile buffer, custom treesitter query), **magenta.nvim** (TypeScript VDOM, 2 buffers).

### session/update

`user_message_chunk`

**codecompanion**:

```md
## Me ─────────────────

{text}

```

H2 header with `CodeCompanionChatHeader` extmark highlight. `─` separator is extmark virtual text (`virt_text_win_col`) filling window width.

**avante**:

```md
> {line1}
> {line2}
```

Every line prefixed with `>` (blockquote style). Rendered in the result buffer alongside assistant output.

**CopilotChat**:

```md
# User (uuid) ---

{text}
```

H1 with UUID. UUID concealed via extmark `conceal = ''`. Overlay extmark shows clean role name.

**magenta**:

```md
# user:

{text}
```

---

`agent_message_chunk`

**agentic**: appended at exact last-line/column via `nvim_buf_set_text`. No header in buffer; role shown in winbar. Auto-scroll via `normal! G0zb`.

**codecompanion**:

```md
## CodeCompanion (model) ─────────────────

{text}
```

Same H2 + extmark separator pattern. Streamed via `nvim_buf_set_text()` through a builder tracking section/block indices. Buffer locked (`modifiable=false`) during generation.

**avante**: streamed into result pane with 50ms throttled batch updates. Assistant header in winbar, not buffer content. Animated spinner via `virt_lines` extmark.

**CopilotChat**:

```md
# Assistant (uuid) ---

{text}
```

Append mode with 150ms debounced treesitter re-parse. `auto_follow_cursor` scrolls during streaming.

**magenta**:

```md
# assistant:

{text}
```

VDOM diff — only changed portions rewritten via `replaceBetweenPositions`.

---

`agent_thought_chunk`

**agentic**: appended in same chat buffer as messages. Transition from thought→message inserts `\n\n` separator. Rendered in `Comment` highlight.

**codecompanion**:

```md
### Reasoning

{text}
```

H3 block, auto-folded when complete (`foldmethod=manual`). Custom `foldtext()` shows summary.

**avante**:

```md
🤔 Thought content:
> {line1}
> {line2}
```

Header + blockquote prefix per line.

**CopilotChat**: rendered as `virt_lines` (virtual lines) placed above the assistant message, not as buffer text.

**magenta**: collapsible thinking block, toggle via `<CR>`.

---

`tool_call`

**agentic**:

```md
╭─  edit(src/main.lua)     [status badge]
│  - old line
│  + new line
╰─                         ✓ completed
```

Box-drawing glyphs via inline extmarks (`virt_text_pos = "inline"`). Status badge on footer as overlay extmark. Five namespaces: tool_blocks (range tracking), decorations, permission_buttons, diff_highlights, status. Per-kind rendering: `read` → "Read N lines" (Comment hl), `edit` → diff with `DiffAdd`/`DiffDelete` + word-level highlights via `vim.diff()` histogram, `execute`/`search`/`fetch` → body text.

**codecompanion**: `TOOL_MESSAGE` type. Status icon overlay at col 0 (`virt_text_pos = "overlay"`): ` ` pending, ` ` in-progress, ` ` completed, ` ` failed. Foldable with icon summary on fold line. Super Diff (`gD`) for multi-file unified view.

**avante**:

```md
╭─  tool_name  state
│   {content}
╰─
```

Box-drawing with state-colored highlights (generating/calling/succeeded/failed). Tracked by UUID. Expand/collapse buttons as right-aligned virtual text. Truncated output: `... (Result truncated, remaining N lines not shown)`.

**CopilotChat**: tool call arguments shown as `virt_lines` (virtual lines below message, formatted JSON). Tool results rendered under a `tool` role H1 header. No inline block decoration.

**magenta**: component with three views toggled via `<CR>`: `renderSummary` (collapsed one-line), `renderPreview` (medium), `renderDetail` (full + usage stats).

---

`tool_call_update`

All plugins patch in-place. **agentic** uses range extmarks to find block boundaries, replaces lines via `nvim_buf_set_lines`. **codecompanion** updates status icon overlay extmark. **avante** re-renders from history (full result buffer re-render). **magenta** VDOM diffs and patches changed nodes.

---

`plan`

**agentic**: rendered in a dedicated `todos` buffer (one of the 5 panels).

**codecompanion**: no dedicated plan rendering observed.

**avante**: rendered in a dedicated `todos` NUI split panel.

---

### session/request_permission

**agentic**:

```md
### Waiting for your response:

 edit(src/main.lua)

1.  ✓ Allow once
2.  ✔ Always allow
3.  ⨯ Reject once
4.  ✗ Always reject
--- ---
```

In-buffer text with buffer-local number keymaps (`1`–`4`). Diff preview available in separate split. Requests queued, displayed sequentially.

**codecompanion**: `vim.ui.select` popup with 4 options (allow always, allow once, reject, cancel). "Yolo mode" toggle bypasses all approvals per-buffer.

**avante**: floating NUI popup (60 chars wide, bordered). Icon buttons: `[Y]es`, `[A]ll yes`, `[N]o`. Keymaps: `y`/`a`/`n`, `h`/`l`/Tab to navigate. Secondary prompt for rejection reason.

**CopilotChat**: handled by Copilot backend, no client-side permission UI.

*
