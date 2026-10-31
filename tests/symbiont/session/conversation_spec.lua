local conversation = require 'symbiont.session.conversation'
local decode = require 'symbiont.client.decode'
local render = require 'symbiont.session.render'
local config = require 'symbiont.config'

local CWD = '/cwd'

local function render_lines(convo)
  return render.conversation(convo, CWD)
end

local function count(list, value)
  local total = 0
  for _, item in ipairs(list) do
    if item == value then
      total = total + 1
    end
  end
  return total
end

local function index_of(list, predicate)
  for index, item in ipairs(list) do
    if predicate(item) then
      return index
    end
  end
  return nil
end

local function tool_call(fields)
  fields.kind = 'tool_call'
  return fields
end

local function user(content)
  return { role = 'user', content = { content } }
end

local function agent(content)
  return { role = 'assistant', content = { content } }
end

describe('conversation', function()
  describe('append_turn (assistant)', function()
    it('merges consecutive text chunks into a single content', function()
      local convo = conversation.new()
      convo:append_turn(agent { kind = 'text', text = 'Hi' })
      convo:append_turn(agent { kind = 'text', text = '!' })
      local result = render_lines(convo)
      assert.equals(6, #result)
      assert.equals(config.header.assistant, result[1])
      assert.equals(config.assistant_message_header, result[3])
      assert.equals('Hi!', result[5])
    end)

    it('does not merge text with thought', function()
      local convo = conversation.new()
      convo:append_turn(agent { kind = 'text', text = 'A' })
      convo:add_thought { kind = 'thought', content = { { kind = 'text', text = 'B' } } }
      local result = render_lines(convo)
      assert.equals('A', result[5])
      assert.equals('', result[6])
      assert.equals(config.thought_header, result[7])
      assert.equals('', result[8])
      assert.equals('> B', result[9])
    end)

    it('does not merge text with image', function()
      local convo = conversation.new()
      convo:append_turn(agent { kind = 'text', text = 'caption' })
      convo:append_turn(agent { kind = 'image', data = 'data', mime_type = 'image/png' })
      local result = render_lines(convo)
      assert.equals('caption', result[5])
      assert.equals('', result[6])
      assert.equals('[image/png](data)', result[7])
    end)

    it('keeps tool_call between two text contents inside one assistant turn', function()
      local convo = conversation.new()
      convo:append_turn(agent { kind = 'text', text = 'before' })
      convo:add_tool_call(tool_call { id = 't1', title = 'Run', tool_kind = 'execute', status = 'completed' })
      convo:append_turn(agent { kind = 'text', text = 'after' })

      local tool = assert(convo:get_tool 't1')
      assert.equals('Run', tool.title)

      local result = render_lines(convo)
      assert.equals(1, count(result, config.header.assistant))
      local before_index = index_of(result, function(line) return line == 'before' end)
      local tool_header_index = index_of(result, function(line) return line == config.tool_call_header end)
      local tool_entry_index = index_of(result, function(line) return line:find('Run', 1, true) end)
      local after_index = index_of(result, function(line) return line == 'after' end)
      assert.truthy(before_index)
      assert.truthy(tool_header_index)
      assert.truthy(tool_entry_index)
      assert.truthy(after_index)
      assert.is_true(before_index < tool_header_index)
      assert.is_true(tool_header_index < tool_entry_index)
      assert.is_true(tool_entry_index < after_index)
    end)
  end)

  describe('add_thought', function()
    it('merges consecutive thought chunks into a single content', function()
      local convo = conversation.new()
      convo:add_thought { kind = 'thought', content = { { kind = 'text', text = 'step ' } } }
      convo:add_thought { kind = 'thought', content = { { kind = 'text', text = 'one' } } }
      local result = render_lines(convo)
      assert.equals(1, count(result, config.thought_header))
      local thought_index = index_of(result, function(line) return line == config.thought_header end)
      assert.equals('', result[thought_index + 1])
      assert.equals('> step one', result[thought_index + 2])
    end)

    it('opens a new assistant turn when none exists', function()
      local convo = conversation.new()
      convo:add_thought { kind = 'thought', content = { { kind = 'text', text = 'alone' } } }
      assert.equals(1, #convo.turns)
      assert.equals('assistant', convo.turns[1].role)
    end)

    it('appends to an existing assistant turn after a tool_call', function()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Run', tool_kind = 'execute', status = 'completed' })
      convo:add_thought { kind = 'thought', content = { { kind = 'text', text = 'after' } } }
      assert.equals(1, #convo.turns)
      assert.equals(2, #convo.turns[1].content)
      assert.equals('thought', convo.turns[1].content[2].kind)
    end)
  end)

  describe('cross-role', function()
    it('does not merge a user text chunk into an agent turn', function()
      local convo = conversation.new()
      convo:append_turn(agent { kind = 'text', text = 'Hi' })
      convo:append_turn(user { kind = 'text', text = 'hello' })
      local result = render_lines(convo)
      assert.equals(1, count(result, config.header.assistant))
      assert.equals(1, count(result, config.header.user))
    end)
  end)

  describe('append_turn (user)', function()
    it('merges consecutive user text chunks', function()
      local convo = conversation.new()
      convo:append_turn(user { kind = 'text', text = 'foo ' })
      convo:append_turn(user { kind = 'text', text = 'bar' })
      local result = render_lines(convo)
      assert.equals(4, #result)
      assert.equals(config.header.user, result[1])
      assert.equals('foo bar', result[3])
    end)
  end)

  describe('add_tool_call', function()
    it('groups consecutive tool_calls under one tool_call_header', function()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Read', tool_kind = 'read', status = 'pending' })
      convo:add_tool_call(tool_call { id = 't2', title = 'Edit', tool_kind = 'edit', status = 'pending' })

      assert.equals('Read', assert(convo:get_tool 't1').title)
      assert.equals('Edit', assert(convo:get_tool 't2').title)

      local result = render_lines(convo)
      assert.equals(1, count(result, config.tool_call_header))
      local read_index = index_of(result, function(line) return line:find('Read', 1, true) end)
      local edit_index = index_of(result, function(line) return line:find('Edit', 1, true) end)
      assert.truthy(read_index)
      assert.truthy(edit_index)
      assert.is_true(read_index < edit_index)
    end)

    it('emits a fresh tool_call_header when text breaks the contiguous tool_call run', function()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Read', tool_kind = 'read', status = 'pending' })
      convo:append_turn(agent { kind = 'text', text = 'between' })
      convo:add_tool_call(tool_call { id = 't2', title = 'Edit', tool_kind = 'edit', status = 'pending' })

      local result = render_lines(convo)
      assert.equals(2, count(result, config.tool_call_header))
      assert.equals(1, count(result, config.header.assistant))
    end)

    it('merges fields from a second add_tool_call with the same id (zed-acp re-emits)', function()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Read File', tool_kind = 'read', status = 'pending', locations = {} })
      convo:add_tool_call(tool_call { id = 't1', title = 'Read File', tool_kind = 'read', status = 'pending', locations = { { path = '/cwd/justfile', line = 0 } } })
      local tool = assert(convo:get_tool 't1')
      assert.same({ { path = '/cwd/justfile', line = 0 } }, tool.locations)
    end)

    it('does not duplicate the content when add_tool_call is re-emitted', function()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Read', tool_kind = 'read', status = 'pending' })
      convo:add_tool_call(tool_call { id = 't1', title = 'Read', tool_kind = 'read', status = 'pending', locations = { { path = '/cwd/justfile' } } })
      local turn = convo.turns[#convo.turns]
      assert.equals(1, #turn.content)
    end)
  end)

  describe('update_tool_call', function()
    local function with_tool()
      local convo = conversation.new()
      convo:add_tool_call(tool_call { id = 't1', title = 'Read', tool_kind = 'read', status = 'pending' })
      return convo
    end

    it('updates status on an existing tool', function()
      local convo = with_tool()
      convo:update_tool_call(tool_call { id = 't1', status = 'in_progress' })
      assert.equals('in_progress', assert(convo:get_tool 't1').status)
    end)

    it('replaces content when call.content is provided', function()
      local convo = with_tool()
      convo:update_tool_call(tool_call { id = 't1', content = { { kind = 'text', text = 'first' } } })
      convo:update_tool_call(tool_call { id = 't1', content = { { kind = 'text', text = 'second' } } })
      assert.same(
        { { kind = 'text', text = 'second' } },
        assert(convo:get_tool 't1').content
      )
    end)

    it('leaves prior fields intact when the update omits them', function()
      local convo = with_tool()
      convo:update_tool_call(tool_call { id = 't1', content = { { kind = 'text', text = 'out' } } })
      convo:update_tool_call(tool_call { id = 't1', status = 'completed' })
      local tool = assert(convo:get_tool 't1')
      assert.equals('completed', tool.status)
      assert.equals('Read', tool.title)
      assert.equals('read', tool.tool_kind)
      assert.same({ { kind = 'text', text = 'out' } }, tool.content)
    end)

    it('is a no-op for unknown tool_id', function()
      local convo = conversation.new()
      convo:update_tool_call(tool_call { id = 'missing', status = 'completed' })
      assert.is_nil(convo:get_tool 'missing')
    end)

    it('updates title, tool_kind, and locations', function()
      local convo = with_tool()
      convo:update_tool_call(tool_call {
        id = 't1',
        title = 'Edit',
        tool_kind = 'edit',
        locations = { { path = '/a', line = 2 } },
      })
      local tool = assert(convo:get_tool 't1')
      assert.equals('Edit', tool.title)
      assert.equals('edit', tool.tool_kind)
      assert.same({ { path = '/a', line = 2 } }, tool.locations)
    end)

    it('renders a status change without a header re-emission', function()
      local convo = with_tool()
      convo:update_tool_call(tool_call {
        id = 't1',
        status = 'completed',
        locations = { { path = 'justfile', line = 0 } },
      })

      local tool = assert(convo:get_tool 't1')
      assert.equals('completed', tool.status)

      local result = render_lines(convo)
      local pending_count = 0
      local completed_count = 0
      for _, line in ipairs(result) do
        if line:find('%[ %]') and line:find 'Read' then
          pending_count = pending_count + 1
        end
        if line:find('%[x%]') and line:find 'Read' then
          completed_count = completed_count + 1
        end
      end
      assert.equals(0, pending_count)
      assert.equals(1, completed_count)
    end)
  end)

  describe('wire to render', function()
    it('decode.tool_call preserves wire-format locations', function()
      local decoded = decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'completed',
        locations = { { path = '/cwd/justfile', line = 1 } },
      }
      assert.same({ { path = '/cwd/justfile', line = 1 } }, decoded.locations)
    end)

    it('add_tool_call keeps locations on the stored tool', function()
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'completed',
        locations = { { path = '/cwd/justfile', line = 1 } },
      })
      assert.same({ { path = '/cwd/justfile', line = 1 } }, assert(convo:get_tool 'tc1').locations)
    end)

    it('render appends the location to the title and omits the body', function()
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'completed',
        locations = { { path = '/cwd/justfile', line = 1 } },
        content = { { type = 'content', content = { type = 'text', text = 'file body' } } },
      })
      local output = table.concat(render.conversation(convo, CWD), '\n')
      assert.truthy(output:find(config.tool_call_header, 1, true), 'tool_call_header must be emitted above the title')
      assert.truthy(output:find('justfile:1', 1, true), 'location should be appended to title')
      assert.is_nil(output:find('file body', 1, true), 'body should be omitted when location is present')
    end)

    it('render shows location after a tool_call_update adds it later', function()
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'pending',
      })
      convo:update_tool_call(decode.tool_call_update {
        toolCallId = 'tc1',
        status = 'completed',
        locations = { { path = '/cwd/justfile' } },
        content = { { type = 'content', content = { type = 'text', text = 'file body' } } },
      })
      local output = table.concat(render.conversation(convo, CWD), '\n')
      assert.truthy(output:find('justfile', 1, true), 'location should appear after update')
      assert.is_nil(output:find('file body', 1, true), 'body should be hidden once location is set')
    end)

    it('survives JSON round-trip through vim.json.decode', function()
      local wire = vim.json.encode {
        sessionUpdate = 'tool_call',
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'completed',
        locations = { { path = '/cwd/justfile', line = 1 } },
        content = { { type = 'content', content = { type = 'text', text = 'file body' } } },
      }
      local update = vim.json.decode(wire)
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call(update))
      local output = table.concat(render.conversation(convo, CWD), '\n')
      assert.truthy(output:find('justfile:1', 1, true))
      assert.is_nil(output:find('file body', 1, true))
    end)

    it('replays the exact zed-acp Read-tool wire sequence', function()
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'pending',
        rawInput = { file_path = '/cwd/justfile' },
        content = {},
        locations = { { path = '/cwd/justfile', line = 0 } },
        _meta = { claudeCode = { toolName = 'Read' } },
      })
      convo:update_tool_call(decode.tool_call_update {
        toolCallId = 'tc1',
        _meta = { claudeCode = { toolName = 'Read' } },
      })
      convo:update_tool_call(decode.tool_call_update {
        toolCallId = 'tc1',
        status = 'completed',
        rawOutput = '...',
        content = { { type = 'content', content = { type = 'text', text = '     1\xE2\x86\x92plugged := env("HOME") / ".local/share/nvim/plugged"\n     2\xE2\x86\x92\n     3\xE2\x86\x92run:' } } },
        _meta = { claudeCode = { toolName = 'Read' } },
      })
      local tool = assert(convo:get_tool 'tc1')
      assert.same({ { path = '/cwd/justfile', line = 0 } }, tool.locations)
      local output = table.concat(render.conversation(convo, CWD), '\n')
      assert.truthy(output:find('justfile', 1, true), 'location should appear: ' .. output)
      assert.is_nil(output:find('plugged :=', 1, true), 'body should be hidden: ' .. output)
    end)

    it('hides previously-rendered body when a later update adds the location', function()
      local convo = conversation.new()
      convo:add_tool_call(decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read File',
        kind = 'read',
        status = 'in_progress',
        content = { { type = 'content', content = { type = 'text', text = 'file body' } } },
      })
      convo:update_tool_call(decode.tool_call_update {
        toolCallId = 'tc1',
        status = 'completed',
        locations = { { path = '/cwd/justfile' } },
      })
      local output = table.concat(render.conversation(convo, CWD), '\n')
      assert.truthy(output:find('justfile', 1, true), 'location should appear after update')
      assert.is_nil(output:find('file body', 1, true), 'body should be hidden once location is set')
    end)
  end)
end)
