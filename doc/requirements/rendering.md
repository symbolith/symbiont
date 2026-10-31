## Headers

`{user_header}` is `config.header.user`.

`{agent_header}` is `config.header.assistant`.

`{assistant_message_header}` is `config.assistant_message_header`.

See [plugin.md](plugin.md) for defaults and configuration.

## Turn structure

A conversation alternates between user and assistant turns only. There is no separate "tool" turn: a `tool_call` is a *content* of the assistant turn, alongside `text`, `thought`, `image`, `link`, and `resource`. The `{agent_header}` is therefore emitted exactly once per assistant response, even when that response interleaves multiple tool calls and additional text.

A tool call's body content (`content` field) uses a narrower set of content kinds: `text`, `image`, `link`, `resource`, and `diff`. Tool call bodies do not nest tool calls, and they do not carry `thought` contents.

## Block composition

Each block template below is **self-contained**: it emits no leading or trailing blank line. Blanks *between* turns come from the conversation joiner (`render.turns`), which inserts a single blank line between adjacent turns. The conversation as a whole is terminated with a final newline.

Blanks *inside* a block (header to body separator, fence boundaries) are part of the block's shape and live inside the renderer.

The same joiner rule applies one level down: when a turn contains multiple contents (for example a `text` content next to a `thought` content, or a tool call body with several content entries), the content joiner inserts one blank line between adjacent contents. Consecutive contents of the same mergeable kind are merged at the conversation layer before rendering, so they reach the renderer as a single content without an internal break.

Contiguous `tool_call` contents inside one assistant turn are grouped under a single `{tool_call_header}`. A non-tool content (e.g. text) breaks the run, so the next batch of tool calls receives a fresh `{tool_call_header}`.

Templates show the block's own lines only. The blank line that appears above each header in a rendered conversation is contributed by the joiner, not by the block.

## Blocks

Types: [acp-messages.md](../research/acp-messages.md).

### session/update

`user_message_chunk`

```md
{user_header}

{ContentBlock}
```

`agent_message_chunk`

```md
{agent_header}

{assistant_message_header}

{ContentBlock}
```

`agent_thought_chunk`

```md
{thought_header}

{ContentBlock}
```

A `thought` is a content of the assistant turn (see [Turn structure](#turn-structure)), so the `{agent_header}` for the enclosing turn is contributed once by the turn renderer, not by the thought block. The blank line between `{thought_header}` and the body is internal to the block.

`tool_call`

```md
{tool_call_header}

{ToolCallStatus} {ToolKind} {title} {ToolCallLocation}

  {ToolCallContent}
```

A `tool_call` is a content of the assistant turn (see [Turn structure](#turn-structure)). The blank line between `{tool_call_header}` and the first entry is internal to the block. The header itself is emitted once per *contiguous run* of tool_call contents inside an assistant turn; adjacent tool_calls inside that run are separated by a single blank line via the content joiner.

If at least one `{ToolCallLocation}` is present, locations are appended to the title line (comma-separated for multiple) and no body is emitted. Otherwise `{ToolCallContent}` is rendered as the body, indented two spaces under the title with a blank line between. Plain text content is wrapped in an unlabeled fenced code block so tool output renders verbatim and is not reparsed as markdown; `resource` and `diff` content already arrive as fenced blocks from their own renderers.

`tool_call_update`

No separate template — patches the existing `tool_call` content in-place by `toolCallId`.

`plan` *(plan buffer only)*
```md
{plan_header}

- {PlanEntryStatus} [{PlanEntryPriority}] {content}
this for all entries
```

### session/request_permission

```md
{permission_header}
**{toolCall.title}**

- [ ] {PermissionOption.name}
- [ ] {PermissionOption.name}
- [ ] {PermissionOption.name}
```


## Sub-type rendering

### ContentBlock

[`TextContent`](../research/acp-messages.md#textcontent)

```md
{text}
```

When `TextContent` arrives via `agent_thought_chunk`, every line is prefixed with `> ` so the chunk renders as a CommonMark blockquote. Blank lines inside the chunk receive the same prefix so the blockquote stays contiguous instead of splitting on the empty line.

[`ImageContent`](../research/acp-messages.md#imagecontent)

```md
[{mimeType}]({uri})
```

[`ResourceLink`](../research/acp-messages.md#resourcelink)

```md
[{title}]({uri}): {description}
```

[`EmbeddedResource`](../research/acp-messages.md#embeddedresource)

```md
```

[`TextResourceContents`](../research/acp-messages.md#textresourcecontents)

````md
```{mimeType}
text
```
````

[`ToolCallLocation`](../research/acp-messages.md#toolcalllocation)

```md
{path}:{line}
```

`{path}` is rendered relative to the **session cwd** — the value Symbiont
sent to the agent at `session/new`, captured once at session creation and
held by the Session for its lifetime. Paths outside the session cwd are
emitted with `../` segments (e.g. `../sibling/file.lua`); paths inside are
stripped of the cwd prefix. The session cwd is decoupled from Neovim's
live cwd: a mid-session `:cd`/`:tcd`/`:lcd` does **not** change rendered
locations, by design — the rendering should match the path namespace the
agent itself sees. If the session needs to be rebased to a new cwd, a new
session must be created.

[`ToolKind`](../research/acp-messages.md#toolkind)

```md
{icon}
```

Icon mapped from kind enum in heading.

[`ToolCallStatus`](../research/acp-messages.md#toolcallstatus)

```md
{icon}
```

Icon mapped from status enum in heading.

[`PlanEntry`](../research/acp-messages.md#planentry)

```md
- {PlanEntryStatus} [{PlanEntryPriority}] {content}
```

[`PermissionOption`](../research/acp-messages.md#permissionoption)

```md
- [ ] {name}
```

### Annotations

[`Annotations`](../research/acp-messages.md#annotations)

- `audience: ["assistant"]` → block not rendered
- `priority < config.priority_threshold` → block rendered inside a fold (collapsed by default)
