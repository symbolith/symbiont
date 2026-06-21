# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Symbiont is a Neovim plugin (pure Lua, no build step) implementing the Agent Client Protocol (ACP) v1. See `doc/requirements/plugin.md` for the full spec (config, commands, session management, rendering pipeline).

## Testing

Tests use plenary.nvim's busted runner:

```bash
# All tests
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Single test file
nvim --headless -c "PlenaryBustedFile tests/symbiont/render_spec.lua {minimal_init = 'tests/minimal_init.lua'}"
```

Requires plenary.nvim at `~/.local/share/nvim/plugged/plenary.nvim`.

## Architecture

Read `doc/architecture/overview.md` for the system context diagram and boundary mechanisms. The architecture docs cover:

- **Module boundaries & dependencies**: `doc/architecture/module-decomposition.md`
- **API signatures**: `doc/architecture/module-interfaces.md`
- **Internal types & wire types**: `doc/architecture/data-structures.md`
- **Message sequences & state mutations**: `doc/architecture/data-flow.md`
- **Threading model & safety invariants**: `doc/architecture/concurrency.md`
- **Error classification & recovery**: `doc/architecture/error-handling.md`
- **Extension points**: `doc/architecture/extension-points.md`

Key structural rules:
- Dependency graph is strictly acyclic (see `doc/architecture/module-decomposition.md`)
- Single session at a time — `init` holds at most one Session reference
- All data mutations and Neovim API calls run inside `vim.schedule` callbacks
- `render` module is pure: no side effects, no Neovim API — unit test it directly
- Wire protocol uses camelCase; plugin normalizes to snake_case internally

## Code Conventions

- LuaCATS type annotations
- OOP pattern for stateful modules: closure-based privacy (`M.new()` returns plain table with `function self:method()` methods; private state as locals in constructor). Private helpers that don't need mutable scalar state can be module-level `local` functions outside `new()`, with state passed as parameters
- Positional arguments for required parameters; opts table for optional fields. Follows `vim.keymap.set(mode, lhs, rhs, opts)` convention
- Input validation via `vim.validate` at API boundaries
- Filetype is `symbiont` (treesitter registers markdown parser for it)
- Block rendering templates are specified in `doc/requirements/rendering.md`
- **Function ordering: visibility groups, definition-before-use within.** Group by visibility: private state, private functions, public methods, side effects. Within each group, define callees before callers (bottom-up) so every function exists before it is referenced, avoiding forward declarations. In a constructor (`M.new()`): private state first, then private helpers (leaf utilities before composed functions), then public methods (lifecycle before domain operations), then side effects (process spawn, initial requests). Module-level files follow the same pattern: local helpers first, exported functions last, `return M` at the bottom
- CODE IS THE SOURCE OF TRUTH! TESTS FOLLOW CODE!
- DO NOT HAVE DEAD CODE JUST FOR TESTS!
- TEST ALL CODE CHANGES AND ADD MISSING TESTS

## Reference

- ACP v1 JSON schema: https://github.com/agentclientprotocol/agent-client-protocol/blob/main/schema/schema.json
- ACP v1 protocol docs: https://agentclientprotocol.com/

## Agent Rules

- NEVER read git history (`git show`, `git log -p`, `git diff --cached`) to access content from deleted or unstaged files. Use only the working tree.
