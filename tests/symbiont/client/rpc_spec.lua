local rpc = require 'symbiont.client.rpc'

local function ndjson(msg)
  return vim.json.encode(msg) .. '\n'
end

describe('rpc', function()
  local decode

  before_each(function()
    decode = rpc.decoder()
  end)

  describe('encode', function()
    it('produces NDJSON', function()
      local msg = { jsonrpc = '2.0', method = 'test', params = { a = 1 } }
      local encoded = rpc.encode(msg)
      assert.truthy(encoded:match '\n$')
      local decoded = vim.json.decode((encoded:gsub('\n$', '')))
      assert.are.same(msg, decoded)
    end)

    it('preserves empty object', function()
      local msg = { jsonrpc = '2.0', method = 'empty', params = vim.empty_dict() }
      local encoded = rpc.encode(msg)
      local decoded = vim.json.decode((encoded:gsub('\n$', '')))
      assert.equals('table', type(decoded.params))
      assert.equals(0, vim.tbl_count(decoded.params))
    end)
  end)

  describe('decode', function()
    it('decodes complete message', function()
      local messages, errors = decode(ndjson { jsonrpc = '2.0', method = 'test' })
      assert.equals(1, #messages)
      assert.equals(0, #errors)
      assert.equals('test', messages[1].method)
    end)

    it('handles chunked delivery', function()
      local line = ndjson { jsonrpc = '2.0', method = 'chunked' }
      local mid = math.floor(#line / 2)
      local messages, _ = decode(line:sub(1, mid))
      assert.equals(0, #messages)
      messages, _ = decode(line:sub(mid + 1))
      assert.equals(1, #messages)
      assert.equals('chunked', messages[1].method)
    end)

    it('decodes multiple messages in single chunk', function()
      local chunk = ndjson { jsonrpc = '2.0', method = 'first' }
        .. ndjson { jsonrpc = '2.0', method = 'second' }
      local messages, _ = decode(chunk)
      assert.equals(2, #messages)
      assert.equals('first', messages[1].method)
      assert.equals('second', messages[2].method)
    end)

    it('waits for incomplete message', function()
      local line = ndjson { jsonrpc = '2.0', method = 'partial' }
      local messages, errors = decode(line:sub(1, #line - 1))
      assert.equals(0, #messages)
      assert.equals(0, #errors)
      messages, _ = decode(line:sub(#line))
      assert.equals(1, #messages)
      assert.equals('partial', messages[1].method)
    end)

    it('returns errors for invalid JSON', function()
      local chunk = '{bad json}\n' .. ndjson { jsonrpc = '2.0', method = 'after_bad' }
      local messages, errors = decode(chunk)
      assert.equals(1, #errors)
      assert.equals('string', type(errors[1]))
      assert.equals(1, #messages)
      assert.equals('after_bad', messages[1].method)
    end)
  end)
end)
