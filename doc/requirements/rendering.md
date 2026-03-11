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

{ContentBlock}

```

`agent_thought_chunk`

```md
{agent_header}

{ContentBlock}

```

`tool_call`

```md
{tool_call_header}

{ToolCallStatus} {ToolKind} {title}
{ToolCallLocation}
{ToolCallContent}
```

`tool_call_update`

No separate template — patches the existing `tool_call` block in-place by `toolCallId`.

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

```md

```
```{mimeType}
text
```
```

```

[`BlobResourceContents`](../research/acp-messages.md#blobresourcecontents) 

[`ToolCallLocation`](../research/acp-messages.md#toolcalllocation)

```md
📍 {path}:{line}
```

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

