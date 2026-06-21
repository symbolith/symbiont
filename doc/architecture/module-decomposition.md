# Module Decomposition

Ownership boundaries, dependency edges, and layering. See [Module Interfaces](module-interfaces.md) for API signatures, [Data Structures](data-structures.md) for types, and [Data Flow](data-flow.md) for message sequences.

## Directory Layout

```
plugin/
└── symbiont.lua
lua/
├── symbiont.lua
└── symbiont/
    ├── client.lua
    ├── client/
    │   ├── rpc.lua
    │   ├── acp.lua
    │   ├── decode.lua
    │   └── encode.lua
    ├── session.lua
    ├── session/
    │   ├── conversation.lua
    │   ├── plan.lua
    │   ├── context.lua
    │   └── mode.lua
    ├── config.lua
    ├── render.lua
    ├── notify.lua
    ├── buffer.lua
    └── health.lua
ftplugin/
└── symbiont.lua
queries/
└── symbiont/
    └── folds.scm
```

## Modules

### symbiont

- Command definitions, plugin state
- Holds list of clients, tracks active session
- Creates clients via `create_client`, wires `on_exit` callback
- `session()` returns active session, creating client + session lazily if needed

### client/

**client**

- Owns agent process and sessions
- Creates Session instances on `session_new`/`session_load`, stores in `sessions` map
- Routes incoming `session/update` notifications to session methods via `decode`
- Routes `session/request_permission` to session's `set_permission`
- Pending request tracking, process lifecycle
- Uses `encode` to convert internal contents to wire format on outbound requests

**rpc**

- Encodes messages to NDJSON lines for stdin
- Decodes NDJSON lines from stdout to messages

**acp**

- Provides functions to create RPC payloads
- ACP type definitions

**decode**

- Converts ACP wire types (camelCase) to internal types (snake_case)
- Functions: `content_block`, `tool_status`, `tool_locations`, `tool_content`, `tool_output`, `tool_call`, `tool_call_update`, `plan_entries`, `permission_request`

**encode**

- Converts internal types (snake_case) to ACP wire types (camelCase)
- Functions: `content_block`, `tool_status`, `tool_locations`, `tool_content`, `tool_output`, `tool_call`, `tool_call_update`, `plan_entries`, `permission_request`

### session/

**session**

- Holds conversation, plan, mode, buffer, permission state
- Receives client reference at construction for RPC delegation
- Provides methods for state mutations (`append_user`, `append_agent`, `update_tool_turn`, `update_tool_call`)
- Delegates outbound RPC to its client (`prompt`, `cancel`, `permission_selected`)

**conversation**

- Ordered block storage
- Rendering: delegates to render module

**plan**

- Plan entry state
- Complete replacement on each update

**context**

- External context capture
- Builds content blocks from non-conversation buffers, renders into the symbiont buffer
- Handles append

**render**

- Transforms conversation, plan, and permission data into markdown lines
- Reads header strings from `config`
- No state

**config**

- Plugin configuration: defaults, user overrides, validation
- Multi-agent: `agents` list with name/cmd per agent, `default_agent`

**notify**

- Notification dispatch via `notification_handler`

**buffer**

- Neovim buffer lifecycle, edit guard, keymaps, rendering

**health**

- `:checkhealth symbiont` integration

## Support Files

**`plugin/symbiont.lua`** — Command registration (`:Symbiont` with subcommands), `BufLeave` and `DirChanged` autocommands.

**`ftplugin/symbiont.lua`** — Buffer-local display options for `filetype=symbiont`.

**`queries/symbiont/folds.scm`** — Treesitter fold query for tool call block folding.

## Acyclic Constraint

The graph is strictly acyclic. Leaf modules (`config`, `rpc`, `acp`, `decode`, `encode`, `plan`, `health`) have no internal dependencies. `render` depends on `config`. `conversation` depends on `render` and `config`. `buffer` depends on `config`. `session` depends on `conversation`, `plan`, `mode`, `render`, and `buffer`. `client` depends on `rpc`, `acp`, `decode`, `encode`, and `session`. `symbiont` depends on `config` and `client`. No module outside `client` references `acp`, `decode`, or `encode`.

Modules load in any order without risk of cycles. Change impact is local: modifying a leaf can only affect its dependents; modifying `config` can affect everything.

`plugin/symbiont.lua` sits outside the module graph — registers commands and autocommands, defers `require("symbiont")` to first invocation.
