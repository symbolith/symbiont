local encode = require 'symbiont.client.encode'

describe('encode', function()
  describe('content_block', function()
    it('text resource emits uri, mimeType, text and no blob', function()
      local block = encode.content_block {
        kind = 'text_resource',
        uri = 'file:///a.txt',
        mime_type = 'text/plain',
        text = 'body',
      }
      assert.same(
        {
          type = 'resource',
          resource = { uri = 'file:///a.txt', mimeType = 'text/plain', text = 'body' },
        },
        block
      )
      assert.is_nil(block.resource.blob)
    end)

    it('blob resource emits uri, mimeType, blob and no text', function()
      local block = encode.content_block {
        kind = 'blob_resource',
        uri = 'file:///a.png',
        mime_type = 'image/png',
        blob = 'AAAA',
      }
      assert.same(
        {
          type = 'resource',
          resource = { uri = 'file:///a.png', mimeType = 'image/png', blob = 'AAAA' },
        },
        block
      )
      assert.is_nil(block.resource.text)
    end)
  end)

end)
