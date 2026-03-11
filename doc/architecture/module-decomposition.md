# Module Decomposition

Ownership boundaries, dependency edges, and layering. See [Module Interfaces](module-interfaces.md) for API signatures, [Data Structures](data-structures.md) for types, and [Data Flow](data-flow.md) for message sequences.

## Dependency Graph

```
plugin/symbiont.lua
└── init
    └── session
        ├── rpc
        ├── acp
        ├── conversation
        ├── plan
        └── buffer
            └── render
    └── config
        health
```

`plugin/symbiont.lua` sits outside the module graph — registers commands and autocommands, defers `require("symbiont")` to first invocation.

## Modules

### init

`lua/symbiont/init.lua` — depends on **config**, **session**

Public API surface and `setup`. Delegates to `session`.

### config

`lua/symbiont/config.lua`

Plugin configuration: defaults, user overrides, validation.

### session

`lua/symbiont/session.lua` — depends on **config**, **rpc**, **acp**, **conversation**, **plan**, **buffer**

Session lifecycle (list/load/new/switch/stop), mode and config option tracking, context capture, permission flow coordination, notification routing.

### rpc

`lua/symbiont/rpc.lua`

JSON-RPC 2.0 transport. No knowledge of ACP semantics.

### acp

`lua/symbiont/acp.lua`

ACP protocol semantics. Request param builders, notification discriminator dispatch, type constant tables. No knowledge of transport or session state.

### conversation

`lua/symbiont/conversation.lua`

Ordered block storage. Message merging, tool call patching.

### plan

`lua/symbiont/plan.lua`

Plan entry state. Complete replacement on each update.

### render

`lua/symbiont/render.lua`

Pure functions: conversation and plan data → markdown lines. No state.

### buffer

`lua/symbiont/buffer.lua` — depends on **config**, **render**

Neovim buffer lifecycle for the conversation buffer and the plan buffer. Separator management, edit guard, keymaps, rendering.

### health

`lua/symbiont/health.lua`

`:checkhealth symbiont` integration.

## Support Files

**`plugin/symbiont.lua`** — Command registration (`:Symbiont`, `:SymbiontMode`, `:SymbiontPlan`), `BufLeave` and `DirChanged` autocommands.

**`ftplugin/symbiont.lua`** — Buffer-local display options for `filetype=symbiont`.

**`queries/symbiont/folds.scm`** — Treesitter fold query for tool call block folding.

## Acyclic Constraint

The graph is strictly acyclic. Leaf modules (`config`, `rpc`, `acp`, `conversation`, `plan`, `render`, `health`) have no internal dependencies. `buffer` depends on `config` and `render`. `session` depends on all leaves plus `buffer`. `init` depends on `config` and `session`.

Modules load in any order without risk of cycles. Change impact is local: modifying a leaf can only affect its dependents; modifying `config` can affect everything.
