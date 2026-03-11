# Architecture

How Symbiont is organized internally. These documents describe the code structure, data flow, module boundaries, and design decisions for the [requirements](../requirements/plugin.md).

Each aspect is covered in its own document:

- [Module Decomposition](module-decomposition.md)
- [Data Flow](data-flow.md)
- [Data Structures](data-structures.md)
- [Module Interfaces](module-interfaces.md)
- [Concurrency](concurrency.md)
- [Error Handling](error-handling.md)
- [Extension Points](extension-points.md)

## System Context

Symbiont runs inside Neovim. Two external actors sit outside the process boundary:

```
                  ┌─────────────────────────────────────┐
                  │              Neovim                 │
                  │                                     │
  ┌──────┐        │  ┌───────────┐                      │
  │      │─edits─────► Buffers   │                      │
  │      │◄reads─────│           │                      │
  │ User │        │  └─────┬─────┘                      │
  │      │        │        │ render / prompt            │
  │      │        │  ┌─────┴──────────┐                 │
  │      │─cmds──────►   Symbiont     │                 │
  └──────┘        │  └───────┬────────┘                 │
                  │          │ stdio / JSON-RPC         │
                  └──────────┼──────────────────────────┘
                             │
                  ┌───────────────────┐
                  │    ACP Agent      │
                  └───────────────────┘
```

**User** — writes prompts, reads rendered conversation, responds to permission requests. Invokes commands and interacts with pickers to switch modes and sessions.

**Neovim** — host process; Symbiont runs inside it, the ACP agent runs outside.

**Buffers** — two Neovim buffers: a conversation buffer containing rendered message blocks (the last user block is the prompt; a read-only guard prevents edits above it) and a read-only plan buffer showing the agent's current plan. Both user and Symbiont converge on these surfaces: the user edits and reads the conversation; Symbiont renders into both and reads prompts from the conversation buffer.

**Symbiont** — the plugin; renders conversation into the buffer, reads prompts from it, relays them to the agent over JSON-RPC.

**ACP Agent** — child process. Owns conversation history, tool execution, plans, and session persistence. Symbiont treats the agent as a black box behind the ACP wire protocol.

| Boundary | Mechanism | Direction |
|---|---|---|
| User ↔ Buffers | Reading, editing in prompt area, keymaps | Bidirectional |
| User ↔ Symbiont | Commands, pickers, notifications | Bidirectional |
| Buffers ↔ Symbiont | Render writes, prompt reads | Bidirectional |
| Symbiont ↔ Agent | JSON-RPC over stdio | Bidirectional |

The plugin owns nothing outside the Neovim process: no network calls, no filesystem writes, no terminal emulation.
