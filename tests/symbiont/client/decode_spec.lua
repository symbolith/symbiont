local decode = require 'symbiont.client.decode'
local encode = require 'symbiont.client.encode'

describe('decode', function()
  describe('content_block', function()
    it('text', function()
      local block = { type = 'text', text = 'hello' }
      assert.same({ kind = 'text', text = 'hello' }, decode.content_block(block))
    end)

    it('image', function()
      local block = { type = 'image', data = 'abc', mimeType = 'image/png' }
      assert.same(
        { kind = 'image', data = 'abc', mime_type = 'image/png' },
        decode.content_block(block)
      )
    end)

    it('resource_link', function()
      local block = { type = 'resource_link', uri = 'https://e.xyz', name = 'Site' }
      assert.same(
        { kind = 'link', uri = 'https://e.xyz', name = 'Site' },
        decode.content_block(block)
      )
    end)

    it('resource with text', function()
      local block = {
        type = 'resource',
        resource = { uri = 'file:///a.txt', text = 'body', mimeType = 'text/plain' },
      }
      assert.same(
        {
          kind = 'text_resource',
          uri = 'file:///a.txt',
          text = 'body',
          mime_type = 'text/plain',
        },
        decode.content_block(block)
      )
    end)

    it('resource with blob', function()
      local block = {
        type = 'resource',
        resource = { uri = 'file:///a.png', blob = 'AAAA', mimeType = 'image/png' },
      }
      local content = decode.content_block(block)
      assert.same(
        {
          kind = 'blob_resource',
          uri = 'file:///a.png',
          blob = 'AAAA',
          mime_type = 'image/png',
        },
        content
      )
      assert.is_nil(content.text)
    end)
  end)

  describe('agent_thought_chunk', function()
    it('text block becomes a thought block wrapping a text content', function()
      local block = { type = 'text', text = 'musing' }
      assert.same(
        { kind = 'thought', content = { { kind = 'text', text = 'musing' } } },
        decode.agent_thought_chunk(block)
      )
    end)

    it('image block becomes a thought block wrapping the image content', function()
      local block = { type = 'image', data = 'abc', mimeType = 'image/png' }
      assert.same(
        {
          kind = 'thought',
          content = { { kind = 'image', data = 'abc', mime_type = 'image/png' } },
        },
        decode.agent_thought_chunk(block)
      )
    end)
  end)

  describe('user_turn', function()
    it('wraps a text content block in a user turn', function()
      local update = { content = { type = 'text', text = 'hi' } }
      assert.same(
        { role = 'user', content = { { kind = 'text', text = 'hi' } } },
        decode.user_turn(update)
      )
    end)

    it('wraps a resource_link content block in a user turn', function()
      local update = { content = { type = 'resource_link', uri = 'https://e.xyz', name = 'Site' } }
      assert.same(
        { role = 'user', content = { { kind = 'link', uri = 'https://e.xyz', name = 'Site' } } },
        decode.user_turn(update)
      )
    end)
  end)

  describe('agent_turn', function()
    it('wraps a text content block in an assistant turn', function()
      local update = { content = { type = 'text', text = 'hello' } }
      assert.same(
        { role = 'assistant', content = { { kind = 'text', text = 'hello' } } },
        decode.agent_turn(update)
      )
    end)

    it('wraps an image content block in an assistant turn', function()
      local update = { content = { type = 'image', data = 'abc', mimeType = 'image/png' } }
      assert.same(
        { role = 'assistant', content = { { kind = 'image', data = 'abc', mime_type = 'image/png' } } },
        decode.agent_turn(update)
      )
    end)
  end)

  describe('tool_contents', function()
    it('returns nil for nil input', function()
      assert.is_nil(decode.tool_contents(nil))
    end)

    it('maps content and diff variants and preserves order', function()
      local result = decode.tool_contents {
        { type = 'content', content = { type = 'text', text = 'line 1' } },
        { type = 'diff', path = '/a.lua', newText = 'new', oldText = 'old' },
        { type = 'content', content = { type = 'text', text = 'line 2' } },
      }
      assert.same({
        { kind = 'text', text = 'line 1' },
        { kind = 'diff', path = '/a.lua', new_text = 'new', old_text = 'old' },
        { kind = 'text', text = 'line 2' },
      }, result)
    end)
  end)

  describe('tool_call', function()
    it('returns a tool_call block carrying kind and id', function()
      local result = decode.tool_call {
        toolCallId = 'tc1',
        title = 'Read',
        kind = 'read',
        status = 'in_progress',
        locations = { { path = '/a', line = 3 } },
        content = { { type = 'content', content = { type = 'text', text = 'x' } } },
      }
      assert.same({
        kind = 'tool_call',
        id = 'tc1',
        title = 'Read',
        tool_kind = 'read',
        status = 'in_progress',
        locations = { { path = '/a', line = 3 } },
        content = { { kind = 'text', text = 'x' } },
      }, result)
    end)

    it('leaves status nil when missing on the wire', function()
      local result = decode.tool_call { toolCallId = 'tc1', title = 'X' }
      assert.is_nil(result.status)
    end)
  end)

  describe('tool_call_update', function()
    it('normalizes present fields and leaves absent ones nil', function()
      local result = decode.tool_call_update {
        toolCallId = 'tc1',
        status = 'completed',
        content = { { type = 'content', content = { type = 'text', text = 'done' } } },
      }
      assert.equals('completed', result.status)
      assert.same({ { kind = 'text', text = 'done' } }, result.content)
      assert.is_nil(result.title)
      assert.is_nil(result.tool_kind)
      assert.is_nil(result.locations)
    end)

    it('passes all-nil when the update has no fields', function()
      local result = decode.tool_call_update { toolCallId = 'tc1' }
      assert.is_nil(result.status)
      assert.is_nil(result.content)
      assert.is_nil(result.title)
      assert.is_nil(result.tool_kind)
      assert.is_nil(result.locations)
    end)
  end)

  describe('round-trip through encode', function()
    it('content_block text', function()
      local block = { type = 'text', text = 'hello' }
      assert.same(block, encode.content_block(decode.content_block(block)))
    end)

    it('content_block image', function()
      local block = { type = 'image', data = 'abc', mimeType = 'image/png' }
      assert.same(block, encode.content_block(decode.content_block(block)))
    end)

    it('content_block resource_link', function()
      local block = { type = 'resource_link', uri = 'https://e.xyz', name = 'Site' }
      assert.same(block, encode.content_block(decode.content_block(block)))
    end)

    it('content_block resource', function()
      local block = {
        type = 'resource',
        resource = { text = 'body', mimeType = 'text/plain' },
      }
      assert.same(block, encode.content_block(decode.content_block(block)))
    end)

  end)
end)
