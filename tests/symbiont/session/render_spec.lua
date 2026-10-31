local render = require 'symbiont.session.render'
local config = require 'symbiont.config'

local CWD = '/cwd'

local function tool_call(fields)
  fields.kind = 'tool_call'
  return fields
end

local function user_turn(content)
  return { turns = { { role = 'user', content = content } } }
end

local function assistant_turn(content)
  return { turns = { { role = 'assistant', content = content } } }
end

local function find_index(lines, predicate)
  for index, line in ipairs(lines) do
    if predicate(line) then
      return index
    end
  end
  return nil
end

local function count(lines, value)
  local total = 0
  for _, line in ipairs(lines) do
    if line == value then
      total = total + 1
    end
  end
  return total
end

describe('render.conversation', function()
  describe('turns', function()
    it('emits user header, blank line, content', function()
      local result = render.conversation(user_turn { { kind = 'text', text = 'hi' } }, CWD)
      assert.equals(config.header.user, result[1])
      assert.equals('', result[2])
      assert.equals('hi', result[3])
    end)

    it('emits assistant header, then message header, above plain text content', function()
      local result = render.conversation(assistant_turn { { kind = 'text', text = 'hello' } }, CWD)
      assert.equals(config.header.assistant, result[1])
      assert.equals('', result[2])
      assert.equals(config.assistant_message_header, result[3])
      assert.equals('', result[4])
      assert.equals('hello', result[5])
    end)

    it('renders multi-line text contents without fencing', function()
      local result = render.conversation(assistant_turn { { kind = 'text', text = 'one\ntwo' } }, CWD)
      assert.equals('one', result[5])
      assert.equals('two', result[6])
      for _, line in ipairs(result) do
        assert.not_equals('```', line)
      end
    end)

    it('separates two turns with a blank line and terminates with a final newline', function()
      local result = render.conversation({
        turns = {
          { role = 'user', content = { { kind = 'text', text = 'hi' } } },
          { role = 'assistant', content = { { kind = 'text', text = 'hey' } } },
        },
      }, CWD)
      assert.equals(config.header.user, result[1])
      assert.equals('', result[2])
      assert.equals('hi', result[3])
      assert.equals('', result[4])
      assert.equals(config.header.assistant, result[5])
      assert.equals('', result[6])
      assert.equals(config.assistant_message_header, result[7])
      assert.equals('', result[8])
      assert.equals('hey', result[9])
      assert.equals('', result[10])
    end)
  end)

  describe('assistant message header', function()
    it('groups contiguous message contents under a single message header', function()
      local result = render.conversation(
        assistant_turn {
          { kind = 'text', text = 'caption' },
          { kind = 'image', mime_type = 'image/png', data = 'AAAA' },
        },
        CWD
      )
      assert.equals(1, count(result, config.assistant_message_header))
      assert.equals(config.assistant_message_header, result[3])
      assert.equals('', result[4])
      assert.equals('caption', result[5])
      assert.equals('', result[6])
      assert.equals('[image/png](AAAA)', result[7])
    end)

    it('emits a fresh message header when a tool_call breaks the message run', function()
      local result = render.conversation(
        assistant_turn {
          { kind = 'text', text = 'before' },
          tool_call { title = 'Run', tool_kind = 'execute', status = 'completed' },
          { kind = 'text', text = 'after' },
        },
        CWD
      )
      assert.equals(2, count(result, config.assistant_message_header))
    end)

    it('does not emit a message header for user turns', function()
      local result = render.conversation(user_turn { { kind = 'text', text = 'hi' } }, CWD)
      assert.equals(0, count(result, config.assistant_message_header))
    end)
  end)

  describe('tool calls', function()
    it('emits assistant header above tool-call header above the title line', function()
      local result = render.conversation(
        assistant_turn { tool_call { title = 'Run', tool_kind = 'execute', status = 'completed' } },
        CWD
      )
      assert.equals(config.header.assistant, result[1])
      assert.equals('', result[2])
      assert.equals(config.tool_call_header, result[3])
      assert.equals('', result[4])
      assert.truthy(result[5]:find 'Run')
    end)

    it('renders title line as a list item with a status checkbox and tool kind icon', function()
      local result = render.conversation(
        assistant_turn { tool_call { title = 'Edit', tool_kind = 'edit', status = 'in_progress' } },
        CWD
      )
      local title = result[5]
      assert.truthy(title:find '^%- %[/%] ', 'starts with `- [/] `')
    end)

    it('appends locations to the title line and emits no body', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Edit',
            tool_kind = 'edit',
            status = 'in_progress',
            locations = { { path = 'a.lua', line = 10 }, { path = 'b.lua' } },
            content = { { kind = 'text', text = 'should not appear' } },
          },
        },
        CWD
      )
      local title_index = find_index(result, function(line)
        return line:find 'Edit a%.lua:10, b%.lua$'
      end)
      assert.truthy(title_index)
      for _, line in ipairs(result) do
        assert.not_equals('should not appear', line)
        assert.is_nil(line:find '> should not appear')
      end
    end)

    it('relativizes absolute path inside cwd', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Edit',
            tool_kind = 'edit',
            status = 'in_progress',
            locations = { { path = '/cwd/foo.lua', line = 4 } },
          },
        },
        CWD
      )
      assert.truthy(find_index(result, function(line)
        return line:find 'foo%.lua:4$'
      end))
    end)

    it('relativizes absolute path outside cwd with ../', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Edit',
            tool_kind = 'edit',
            status = 'in_progress',
            locations = { { path = '/sibling/bar.lua' } },
          },
        },
        CWD
      )
      assert.truthy(find_index(result, function(line)
        return line:find '%.%./sibling/bar%.lua$'
      end))
    end)

    it('relativizes path needing multiple ../ segments', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Edit',
            tool_kind = 'edit',
            status = 'in_progress',
            locations = { { path = '/other/branch/leaf.lua' } },
          },
        },
        '/cwd/a/b'
      )
      assert.truthy(find_index(result, function(line)
        return line:find '%.%./%.%./%.%./other/branch/leaf%.lua$'
      end))
    end)

    it('prefixes text content with a blockquote indented under the title with a blank line above', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Search',
            tool_kind = 'search',
            status = 'completed',
            content = { { kind = 'text', text = 'hit one\nhit two' } },
          },
        },
        CWD
      )
      local title_index = assert(find_index(result, function(line)
        return line:find 'Search'
      end))
      assert.equals('', result[title_index + 1])
      assert.equals('  > hit one', result[title_index + 2])
      assert.equals('  > hit two', result[title_index + 3])
    end)

    it('renders an assistant turn whose content mixes text and a tool_call under one agent header', function()
      local result = render.conversation(
        assistant_turn {
          { kind = 'text', text = 'thinking' },
          tool_call { title = 'Run', tool_kind = 'execute', status = 'completed' },
        },
        CWD
      )
      assert.equals(1, count(result, config.header.assistant))
      assert.equals(config.header.assistant, result[1])
      assert.equals('', result[2])
      assert.equals(config.assistant_message_header, result[3])
      assert.equals('', result[4])
      assert.equals('thinking', result[5])
      assert.equals('', result[6])
      assert.equals(config.tool_call_header, result[7])
      assert.equals('', result[8])
      assert.truthy(result[9]:find 'Run')
    end)

    it('renders an assistant turn whose tool_call is followed by more text without repeating the agent header', function()
      local result = render.conversation(
        assistant_turn {
          tool_call { title = 'Run', tool_kind = 'execute', status = 'completed' },
          { kind = 'text', text = 'after' },
        },
        CWD
      )
      assert.equals(1, count(result, config.header.assistant))
      assert.equals(1, count(result, config.tool_call_header))
      local title_index = assert(find_index(result, function(line)
        return line:find 'Run'
      end))
      local after_index = assert(find_index(result, function(line)
        return line == 'after'
      end))
      assert.is_true(after_index > title_index)
      assert.equals('', result[after_index - 1])
    end)

    it('stacks two contiguous bodyless tool_calls without a blank line under one tool-call header', function()
      local result = render.conversation(
        assistant_turn {
          tool_call { title = 'Run1', tool_kind = 'execute', status = 'completed' },
          tool_call { title = 'Run2', tool_kind = 'execute', status = 'completed' },
        },
        CWD
      )
      assert.equals(1, count(result, config.tool_call_header))
      local first_index = assert(find_index(result, function(line)
        return line:find 'Run1'
      end))
      local second_index = assert(find_index(result, function(line)
        return line:find 'Run2'
      end))
      assert.equals(first_index + 1, second_index)
    end)

    it('separates two contiguous bodied tool_calls with a single blank line', function()
      local result = render.conversation(
        assistant_turn {
          tool_call {
            title = 'Run1',
            tool_kind = 'execute',
            status = 'completed',
            content = { { kind = 'text', text = 'output1' } },
          },
          tool_call {
            title = 'Run2',
            tool_kind = 'execute',
            status = 'completed',
            content = { { kind = 'text', text = 'output2' } },
          },
        },
        CWD
      )
      local second_index = assert(find_index(result, function(line)
        return line:find 'Run2'
      end))
      assert.equals('', result[second_index - 1])
    end)

    it('emits a fresh tool-call header when a text content breaks a tool_call run', function()
      local result = render.conversation(
        assistant_turn {
          tool_call { title = 'Run1', tool_kind = 'execute', status = 'completed' },
          { kind = 'text', text = 'middle' },
          tool_call { title = 'Run2', tool_kind = 'execute', status = 'completed' },
        },
        CWD
      )
      assert.equals(2, count(result, config.tool_call_header))
    end)
  end)

  describe('content separation', function()
    it('separates a text content and a thought block with a blank line', function()
      local result = render.conversation(
        assistant_turn {
          { kind = 'text', text = 'plain' },
          { kind = 'thought', content = { { kind = 'text', text = 'pondering' } } },
        },
        CWD
      )
      local text_index = assert(find_index(result, function(line)
        return line == 'plain'
      end))
      local header_index = assert(find_index(result, function(line)
        return line == config.thought_header
      end))
      assert.equals(text_index + 2, header_index)
      assert.equals('', result[text_index + 1])
      assert.equals('', result[header_index + 1])
      assert.equals('> pondering', result[header_index + 2])
    end)

    it('separates adjacent content items with a single blank line', function()
      local result = render.conversation(
        user_turn {
          { kind = 'text', text = 'first' },
          { kind = 'link', name = 'docs', uri = 'https://example.com' },
          { kind = 'thought', content = { { kind = 'text', text = 'pondering' } } },
        },
        CWD
      )
      assert.equals('first', result[3])
      assert.equals('', result[4])
      assert.equals('[docs](https://example.com)', result[5])
      assert.equals('', result[6])
      assert.equals(config.thought_header, result[7])
      assert.equals('', result[8])
      assert.equals('> pondering', result[9])
    end)

    it('separates a thought, a text, and a thought with single blank lines', function()
      local result = render.conversation(
        user_turn {
          { kind = 'thought', content = { { kind = 'text', text = 'before' } } },
          { kind = 'text', text = 'middle' },
          { kind = 'thought', content = { { kind = 'text', text = 'after' } } },
        },
        CWD
      )
      assert.equals(config.thought_header, result[3])
      assert.equals('', result[4])
      assert.equals('> before', result[5])
      assert.equals('', result[6])
      assert.equals('middle', result[7])
      assert.equals('', result[8])
      assert.equals(config.thought_header, result[9])
      assert.equals('', result[10])
      assert.equals('> after', result[11])
    end)
  end)

  describe('per-kind renderers', function()
    local function body_line(content_item)
      local result = render.conversation(user_turn { content_item }, CWD)
      return result[3]
    end

    local function body_lines(content_item)
      local result = render.conversation(user_turn { content_item }, CWD)
      local lines = {}
      for index = 3, #result - 1 do
        lines[#lines + 1] = result[index]
      end
      return lines
    end

    it('text renders as the raw text', function()
      assert.equals('hello world', body_line { kind = 'text', text = 'hello world' })
    end)

    it('thought single-line text gets a blockquote marker under a thought header', function()
      assert.same(
        { config.thought_header, '', '> pondering' },
        body_lines { kind = 'thought', content = { { kind = 'text', text = 'pondering' } } }
      )
    end)

    it('thought prefixes every line of multi-line text', function()
      assert.same(
        { config.thought_header, '', '> first', '> second' },
        body_lines { kind = 'thought', content = { { kind = 'text', text = 'first\nsecond' } } }
      )
    end)

    it('thought prefixes blank lines so the blockquote stays contiguous', function()
      assert.same(
        { config.thought_header, '', '> first', '> ', '> second' },
        body_lines { kind = 'thought', content = { { kind = 'text', text = 'first\n\nsecond' } } }
      )
    end)

    it('image renders as [mime](data)', function()
      assert.equals('[image/png](AAAA)', body_line { kind = 'image', mime_type = 'image/png', data = 'AAAA' })
    end)

    it('link renders as [name](uri)', function()
      assert.equals('[docs](https://example.com)', body_line { kind = 'link', name = 'docs', uri = 'https://example.com' })
    end)

    it('text resource renders as a fenced code block tagged with mime type', function()
      assert.same(
        { '```text/lua', 'print(1)', '```' },
        body_lines {
          kind = 'text_resource',
          uri = 'file:///a.lua',
          mime_type = 'text/lua',
          text = 'print(1)',
        }
      )
    end)

    it('blob resource renders as a uri placeholder link', function()
      assert.equals(
        '[file:///a.png]',
        body_line {
          kind = 'blob_resource',
          uri = 'file:///a.png',
          mime_type = 'image/png',
          blob = 'AAAA',
        }
      )
    end)

    it('diff renders without old_text', function()
      assert.same(
        { '```diff', '+added', '', '```' },
        body_lines { kind = 'diff', path = 'a.lua', new_text = '+added\n' }
      )
    end)

    it('diff renders with old_text and new_text', function()
      assert.same(
        { '```diff', '-old', '+new', '', '```' },
        body_lines {
          kind = 'diff',
          path = 'a.lua',
          old_text = '-old\n',
          new_text = '+new\n',
        }
      )
    end)
  end)
end)
