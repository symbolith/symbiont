# ACP Messages

Methods used by the plugin. Types documented under the method that introduces them.

Source: [ACP v1 schema](https://github.com/agentclientprotocol/agent-client-protocol/blob/main/schema/schema.json).

## Agent → Client

**session/update**

Streams session state changes during prompt processing.

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `update` | [`SessionUpdate`](#sessionupdate) | yes |

### SessionUpdate

Discriminated on `sessionUpdate`:

| `sessionUpdate` | Payload |
|---|---|
| `user_message_chunk` | [`ContentChunk`](#contentchunk) |
| `agent_message_chunk` | [`ContentChunk`](#contentchunk) |
| `agent_thought_chunk` | [`ContentChunk`](#contentchunk) |
| `tool_call` | [`ToolCall`](#toolcall) |
| `tool_call_update` | [`ToolCallUpdate`](#toolcallupdate) |
| `plan` | [`Plan`](#plan) |
| `current_mode_update` | [`CurrentModeUpdate`](#currentmodeupdate) |
| `available_commands_update` | [`AvailableCommandsUpdate`](#availablecommandsupdate) |
| `config_option_update` | [`ConfigOptionUpdate`](#configoptionupdate) |

### ContentChunk

| Field | Type | Required |
|---|---|---|
| `content` | [`ContentBlock`](#contentblock) | yes |

### ContentBlock

Discriminated on `type`:

| `type` | Payload |
|---|---|
| `"text"` | [`TextContent`](#textcontent) |
| `"image"` | [`ImageContent`](#imagecontent) |
| `"resource_link"` | [`ResourceLink`](#resourcelink) |
| `"resource"` | [`EmbeddedResource`](#embeddedresource) |

### TextContent

| Field | Type | Required |
|---|---|---|
| `text` | `string` | yes |
| `annotations` | [`Annotations`](#annotations) | no |

### ImageContent

| Field | Type | Required |
|---|---|---|
| `data` | `string` (base64) | yes |
| `mimeType` | `string` | yes |
| `uri` | `string` | no |
| `annotations` | [`Annotations`](#annotations) | no |

### ResourceLink

| Field | Type | Required |
|---|---|---|
| `uri` | `string` | yes |
| `name` | `string` | yes |
| `mimeType` | `string` | no |
| `title` | `string` | no |
| `description` | `string` | no |
| `size` | `integer` | no |
| `annotations` | [`Annotations`](#annotations) | no |

### EmbeddedResource

| Field | Type | Required |
|---|---|---|
| `resource` | [`TextResourceContents`](#textresourcecontents) \| [`BlobResourceContents`](#blobresourcecontents) | yes |
| `annotations` | [`Annotations`](#annotations) | no |

### TextResourceContents

`{ uri: string, text: string, mimeType?: string }`

### BlobResourceContents

`{ uri: string, blob: string (base64), mimeType?: string }`

### Annotations

| Field | Type | Required |
|---|---|---|
| `audience` | `Role[]` (`"assistant"` \| `"user"`) | no |
| `lastModified` | `string` | no |
| `priority` | `number` | no |

### ToolCall

| Field | Type | Required |
|---|---|---|
| `toolCallId` | `string` | yes |
| `title` | `string` | yes |
| `kind` | [`ToolKind`](#toolkind) | no |
| `status` | [`ToolCallStatus`](#toolcallstatus) | no |
| `content` | [`ToolCallContent[]`](#toolcallcontent) | no |
| `locations` | [`ToolCallLocation[]`](#toolcalllocation) | no |
| `rawInput` | `object` | no |
| `rawOutput` | `object` | no |

### ToolCallUpdate

All fields except `toolCallId` optional. `content` and `locations` **replace** existing arrays. `status`, `title`, `kind` replace scalars.

| Field | Type | Required |
|---|---|---|
| `toolCallId` | `string` | yes |
| `title` | `string` | no |
| `kind` | [`ToolKind`](#toolkind) | no |
| `status` | [`ToolCallStatus`](#toolcallstatus) | no |
| `content` | [`ToolCallContent[]`](#toolcallcontent) | no |
| `locations` | [`ToolCallLocation[]`](#toolcalllocation) | no |
| `rawInput` | `object` | no |
| `rawOutput` | `object` | no |

### ToolKind

`read`, `edit`, `delete`, `move`, `search`, `execute`, `think`, `fetch`, `switch_mode`, `other`

### ToolCallStatus

| Value | Description |
|---|---|
| `pending` | Not started; input streaming or awaiting approval |
| `in_progress` | Currently executing |
| `completed` | Finished successfully |
| `failed` | Error |

### ToolCallContent

Discriminated on `type`:

**`"content"`**: `{ content: `[`ContentBlock`](#contentblock)` }`
**`"diff"`**: `{ path: string, newText: string, oldText?: string }`
**`"terminal"`**: `{ terminalId: string }`

### ToolCallLocation

| Field | Type | Required |
|---|---|---|
| `path` | `string` | yes |
| `line` | `integer` | no |

### Plan

| Field | Type | Required |
|---|---|---|
| `entries` | [`PlanEntry[]`](#planentry) | yes |

Complete replacement on each update.

### PlanEntry

| Field | Type | Required | Values |
|---|---|---|---|
| `content` | `string` | yes | task description |
| `priority` | `PlanEntryPriority` | yes | `high`, `medium`, `low` |
| `status` | `PlanEntryStatus` | yes | `pending`, `in_progress`, `completed` |

### CurrentModeUpdate

| Field | Type | Required |
|---|---|---|
| `currentModeId` | `string` | yes |

### AvailableCommandsUpdate

| Field | Type | Required |
|---|---|---|
| `availableCommands` | [`AvailableCommand[]`](#availablecommand) | yes |

### AvailableCommand

| Field | Type | Required |
|---|---|---|
| `name` | `string` | yes |
| `description` | `string` | yes |
| `input` | [`AvailableCommandInput`](#availablecommandinput) | no |

### AvailableCommandInput

`{ unstructured?: { hint: string } }`

### ConfigOptionUpdate

| Field | Type | Required |
|---|---|---|
| `configOptions` | [`SessionConfigOption[]`](#sessionconfigoption) | yes |

**session/request_permission**

Agent requests user permission before sensitive operations. Client must respond.

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `toolCall` | [`ToolCallUpdate`](#toolcallupdate) | yes |
| `options` | [`PermissionOption[]`](#permissionoption) | yes |

### PermissionOption

| Field | Type | Required |
|---|---|---|
| `optionId` | `string` | yes |
| `name` | `string` | yes |
| `kind` | [`PermissionOptionKind`](#permissionoptionkind) | yes |

### PermissionOptionKind

`allow_once`, `allow_always`, `reject_once`, `reject_always`

→ [`RequestPermissionOutcome`](#requestpermissionoutcome)

### RequestPermissionOutcome

Discriminated on `outcome`:

- `{ outcome: "selected", optionId: string }` — user picked an option
- `{ outcome: "cancelled" }` — prompt turn cancelled via `session/cancel`

## Client → Agent

**initialize**

Establishes connection, negotiates capabilities.

| Field | Type | Required |
|---|---|---|
| `protocolVersion` | `integer` | yes |
| `clientInfo` | [`Implementation`](#implementation) | no |
| `clientCapabilities` | [`ClientCapabilities`](#clientcapabilities) | no |

### Implementation

`{ name: string, version: string, title?: string }`

### ClientCapabilities

| Field | Type | Default |
|---|---|---|
| `fs.readTextFile` | `boolean` | `false` |
| `fs.writeTextFile` | `boolean` | `false` |
| `terminal` | `boolean` | `false` |

→ [`InitializeResponse`](#initializeresponse)

### InitializeResponse

| Field | Type | Required |
|---|---|---|
| `protocolVersion` | `integer` | yes |
| `agentInfo` | [`Implementation`](#implementation) | no |
| `agentCapabilities` | [`AgentCapabilities`](#agentcapabilities) | no |
| `authMethods` | [`AuthMethod[]`](#authmethod) | no |

### AgentCapabilities

| Field | Type | Default |
|---|---|---|
| `loadSession` | `boolean` | `false` |
| `promptCapabilities.image` | `boolean` | `false` |
| `promptCapabilities.audio` | `boolean` | `false` |
| `promptCapabilities.embeddedContext` | `boolean` | `false` |

### AuthMethod

`{ id: string, name: string, description?: string }`

**session/list** *(unstable)*

Lists existing sessions. Requires `listSessions` agent capability.

| Field | Type | Required |
|---|---|---|
| `cwd` | `string` | no |
| `cursor` | `string` | no |

→ Response:

| Field | Type | Required |
|---|---|---|
| `sessions` | [`SessionInfo[]`](#sessioninfo) | yes |
| `nextCursor` | `string` | no |

### SessionInfo

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `cwd` | `string` | yes |
| `title` | `string` | no |
| `updatedAt` | `string` (ISO 8601) | no |

**session/new**

Creates a new session.

| Field | Type | Required |
|---|---|---|
| `cwd` | `string` (absolute) | yes |
| `mcpServers` | `McpServer[]` | yes |

→ Response:

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `modes` | [`SessionModeState`](#sessionmodestate) | no |
| `configOptions` | [`SessionConfigOption[]`](#sessionconfigoption) | no |

### SessionModeState

| Field | Type | Required |
|---|---|---|
| `currentModeId` | `string` | yes |
| `availableModes` | [`SessionMode[]`](#sessionmode) | yes |

### SessionMode

`{ id: string, name: string, description?: string }`

### SessionConfigOption

Discriminated union on `type`. Common fields:

| Field | Type | Required |
|---|---|---|
| `id` | `string` | yes |
| `name` | `string` | yes |
| `type` | `string` | yes |
| `description` | `string` | no |
| `category` | [`SessionConfigOptionCategory`](#sessionconfigoptioncategory) | no |

**`"select"`** variant adds:

| Field | Type | Required |
|---|---|---|
| `currentValue` | `string` | yes |
| `options` | [`SessionConfigSelectOption[]`](#sessionconfigselectoption) \| [`SessionConfigSelectGroup[]`](#sessionconfigselectgroup) | yes |

### SessionConfigOptionCategory

`mode`, `model`, `thought_level` (extensible)

### SessionConfigSelectOption

`{ value: string, name: string, description?: string }`

### SessionConfigSelectGroup

`{ group: string, name: string, options: `[`SessionConfigSelectOption[]`](#sessionconfigselectoption)` }`

**session/load**

Loads an existing session. Requires `loadSession` agent capability.

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `cwd` | `string` | yes |
| `mcpServers` | `McpServer[]` | yes |

→ `{ modes?: `[`SessionModeState`](#sessionmodestate)`, configOptions?: `[`SessionConfigOption[]`](#sessionconfigoption)` }`

**session/prompt**

Sends user message to agent. Response comes after all `session/update` notifications.

| Field | Type | Required |
|---|---|---|
| `sessionId` | `string` | yes |
| `prompt` | [`ContentBlock[]`](#contentblock) | yes |

→ `{ stopReason: `[`StopReason`](#stopreason)` }`

### StopReason

`end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`

**session/cancel**

Cancels ongoing operations. No response.

`{ sessionId: string }`

**session/set_mode**

Changes the session mode.

`{ sessionId: string, modeId: string }`

→ `{}`
