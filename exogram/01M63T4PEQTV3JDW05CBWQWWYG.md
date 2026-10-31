---
aliases:
  - Symbiont 0.1.0
type:
  - "[Type ComputerProgram](01M617D5N48P6VER6YPKHMNFXA.md)"
realizationOf:
  - "[Software Symbiont](20250422172822.md)"
versionIdentifier: "0.1.0"
comment: "an ACP v1 client that chats with one agent"
vetting: unread
---

## Architecture

```text
            Plugin                       Bot

channel1:   PluginSender    --Request->  BotReciever
channel2:   PluginReceiver  <-Response-  BotSender
```

## Linking

- File(s) -> ChatMd

## Context

- Cursor position
- Selection
- Opened file
- Repo

## Selection

## Response

## Keymaps

```text
cTn v n File NewChat with template
cn  v n File NewChat with default template
cc    n File ToogleChat
cc  v   File AppendChat

CTn v n Repo NewChat with template
Cn  v n Repo NewChat with default template
Cc    n Repo ToogleChat
Cc  v   Repo AppendChat

caX Add context
crX Remove context

T = Template
X = Context
```

## Md file formant

## System prompt

- Markdown headings start at ###

### Notes

```rust
fn test_lua() -> nvim_oxi::Result<()> {
    print!("Hello from nvim-oxi..");
    let lua = mlua::lua();
    let print: LuaFunction = lua.globals().get("print")?;
    print.call::<()>("..and goodbye from mlua!")?;

    let x: Table = lua.globals().get("vim").unwrap();
    let x: LuaFunction = x.get("uri_from_bufnr")?;
    // let y: Table = lua.globals().metatable().unwrap_or_default();
    let x = x.call::<String>(0)?;
    //
    print.call::<()>(x)?;

    Ok(())
}
```
