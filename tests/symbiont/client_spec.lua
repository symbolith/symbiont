local coop = require 'coop'
local Client = require 'symbiont.client'

local function ndjson(message)
  return vim.json.encode(message) .. '\n'
end

describe('client', function()
  local written, feed
  local original_system, original_schedule

  before_each(function()
    original_system = vim.system
    original_schedule = vim.schedule
    rawset(vim, 'schedule', function(fn) fn() end)
  end)

  after_each(function()
    rawset(vim, 'system', original_system)
    rawset(vim, 'schedule', original_schedule)
  end)

  local function last_sent()
    return vim.json.decode((written[#written]:gsub('\n$', '')))
  end

  local function new_client(on_exit)
    written = {}
    local stdout_fn
    rawset(vim, 'system', function(_, opts)
      stdout_fn = opts.stdout
      return {
        write = function(_, data)
          table.insert(written, data)
        end,
        kill = function() end,
      }
    end)
    local instance
    coop.spawn(function()
      instance = Client.new({ 'mock' }, on_exit or function() end)
    end)
    feed = function(chunk)
      stdout_fn(nil, chunk)
    end
    local init_id = last_sent().id
    feed(ndjson { jsonrpc = '2.0', id = init_id, result = { agentCapabilities = {} } })
    written = {}
    return instance
  end

  local function create_session(instance, session_id)
    local session
    coop.spawn(function()
      session = instance:session_new('/tmp')
    end)
    local message = last_sent()
    feed(ndjson { jsonrpc = '2.0', id = message.id, result = { sessionId = session_id } })
    written = {}
    return session
  end

  it('new spawns process and returns initialized client', function()
    written = {}
    local stdout_fn
    rawset(vim, 'system', function(_, opts)
      stdout_fn = opts.stdout
      return {
        write = function(_, data) table.insert(written, data) end,
        kill = function() end,
      }
    end)
    local instance
    coop.spawn(function()
      instance = Client.new({ 'mock' }, function() end)
    end)
    local message = last_sent()
    assert.equals('2.0', message.jsonrpc)
    assert.equals('initialize', message.method)
    assert.equals('symbiont.nvim', message.params.clientInfo.name)
    assert.is_number(message.id)
    assert.is_nil(instance)
    stdout_fn(nil, ndjson { jsonrpc = '2.0', id = message.id, result = { agentCapabilities = { loadSession = true } } })
    assert.not_equals(nil, instance)
    assert.is_true(instance.agent_capabilities.loadSession)
  end)

  it('new returns nil and error on initialize failure', function()
    written = {}
    local stdout_fn
    rawset(vim, 'system', function(_, opts)
      stdout_fn = opts.stdout
      return {
        write = function(_, data) table.insert(written, data) end,
        kill = function() end,
      }
    end)
    local instance, init_error
    coop.spawn(function()
      instance, init_error = Client.new({ 'mock' }, function() end)
    end)
    local message = last_sent()
    stdout_fn(nil, ndjson { jsonrpc = '2.0', id = message.id, error = { code = -1, message = 'fail' } })
    assert.is_nil(instance)
    assert.is_truthy(init_error:find('fail'))
  end)

  it('session_new creates and stores session', function()
    local instance = new_client()
    local session
    coop.spawn(function()
      session = instance:session_new('/tmp')
    end)
    local message = last_sent()
    feed(ndjson { jsonrpc = '2.0', id = message.id, result = { sessionId = 'abc' } })
    assert.equals('abc', session.session_id)
    assert.equals(session, instance.sessions['abc'])
  end)

  it('error response raises in calling task', function()
    local instance = new_client()
    local task_error
    coop.spawn(function()
      local ok, error_value = pcall(instance.session_new, instance, '/tmp')
      if not ok then task_error = error_value end
    end)
    local message = last_sent()
    feed(ndjson { jsonrpc = '2.0', id = message.id, error = { code = -1, message = 'fail' } })
    assert.not_equals(nil, task_error)
    assert.is_truthy(task_error:find('fail'))
  end)

  it('unknown response id silently dropped', function()
    new_client()
    local ok = pcall(feed, ndjson { jsonrpc = '2.0', id = 999, result = {} })
    assert.is_true(ok)
  end)

  it('session/update routes to session methods', function()
    local instance = new_client()
    create_session(instance, 's1')

    feed(ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 's1',
        update = { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'hello' } },
      },
    })

    feed(ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 's1',
        update = { sessionUpdate = 'current_mode_update', currentModeId = 'architect' },
      },
    })
  end)

  it('agent_thought_chunk dispatches a thought to session.add_thought', function()
    local instance = new_client()
    create_session(instance, 's1')

    local recorded = {}
    instance.sessions['s1'] = {
      add_thought = function(_, thought)
        recorded[#recorded + 1] = thought
      end,
    }

    feed(ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 's1',
        update = { sessionUpdate = 'agent_thought_chunk', content = { type = 'text', text = 'musing' } },
      },
    })

    assert.equals(1, #recorded)
    assert.same(
      { kind = 'thought', content = { { kind = 'text', text = 'musing' } } },
      recorded[1]
    )
  end)

  it('tool_call followed by tool_call_update patches status and contents', function()
    local instance = new_client()
    local session = create_session(instance, 's1')

    feed(ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 's1',
        update = {
          sessionUpdate = 'tool_call',
          toolCallId = 'tc1',
          title = 'Read',
          kind = 'read',
          status = 'pending',
        },
      },
    })

    local tool = assert(session:get_tool 'tc1')
    assert.equals('pending', tool.status)
    assert.equals('Read', tool.title)
    assert.is_nil(tool.content)

    feed(ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 's1',
        update = {
          sessionUpdate = 'tool_call_update',
          toolCallId = 'tc1',
          status = 'completed',
          content = { { type = 'content', content = { type = 'text', text = 'hit one' } } },
        },
      },
    })

    tool = assert(session:get_tool 'tc1')
    assert.equals('completed', tool.status)
    assert.equals('Read', tool.title)
    assert.same({ { kind = 'text', text = 'hit one' } }, tool.content)
  end)

  it('session/update ignores unknown session', function()
    new_client()
    local ok = pcall(feed, ndjson {
      jsonrpc = '2.0',
      method = 'session/update',
      params = {
        sessionId = 'nonexistent',
        update = { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'hi' } },
      },
    })
    assert.is_true(ok)
  end)

  it('session/request_permission sets permission on session', function()
    local instance = new_client()
    create_session(instance, 's1')

    feed(ndjson {
      jsonrpc = '2.0',
      id = 42,
      method = 'session/request_permission',
      params = {
        sessionId = 's1',
        toolCall = { toolCallId = 'tc1', title = 'bash' },
        options = { { optionId = 'allow', name = 'Allow', kind = 'allow_once' } },
      },
    })
  end)

  it('cancel sends notification', function()
    local instance = new_client()
    instance:cancel('sess-1')
    local message = last_sent()
    assert.equals('session/cancel', message.method)
    assert.equals('sess-1', message.params.sessionId)
    assert.is_nil(rawget(message, 'id'))
  end)

  it('prompt translates contents and sends request', function()
    local instance = new_client()
    instance:prompt('sess-1', { { kind = 'text', text = 'hello' } })
    local message = last_sent()
    assert.equals('session/prompt', message.method)
    assert.equals('sess-1', message.params.sessionId)
    assert.equals('text', message.params.prompt[1].type)
    assert.equals('hello', message.params.prompt[1].text)
    assert.is_number(message.id)
  end)

  it('set_mode sends request', function()
    local instance = new_client()
    instance:set_mode('sess-1', 'mode-1')
    local message = last_sent()
    assert.equals('session/setMode', message.method)
    assert.equals('sess-1', message.params.sessionId)
    assert.equals('mode-1', message.params.modeId)
    assert.is_number(message.id)
  end)

  it('set_config_option sends request', function()
    local instance = new_client()
    instance:set_config_option('sess-1', 'opt-1', true)
    local message = last_sent()
    assert.equals('session/setConfigOption', message.method)
    assert.equals('sess-1', message.params.sessionId)
    assert.equals('opt-1', message.params.configOptionId)
    assert.is_true(message.params.value)
  end)

  it('permission_selected sends response', function()
    local instance = new_client()
    instance:permission_selected(42, 'opt-1')
    local message = last_sent()
    assert.equals(42, message.id)
    assert.equals('selected', message.result.outcome)
    assert.equals('opt-1', message.result.optionId)
  end)

  it('permission_cancelled sends response', function()
    local instance = new_client()
    instance:permission_cancelled(42)
    local message = last_sent()
    assert.equals(42, message.id)
    assert.equals('cancelled', message.result.outcome)
    assert.is_nil(rawget(message.result, 'optionId'))
  end)

  it('malformed JSON notifies warning', function()
    local notifications = {}
    local original_notify = vim.notify
    rawset(vim, 'notify', function(message, level)
      table.insert(notifications, { message = message, level = level })
    end)
    new_client()
    feed '{bad json}\n'
    rawset(vim, 'notify', original_notify)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.WARN, notifications[1].level)
  end)

  it('process exit clears sessions and calls on_exit', function()
    local exit_args = {}
    written = {}
    local stdout_fn, exit_fn
    rawset(vim, 'system', function(_, opts, on_exit)
      stdout_fn = opts.stdout
      exit_fn = on_exit
      return {
        write = function(_, data) table.insert(written, data) end,
        kill = function() end,
      }
    end)
    local instance
    coop.spawn(function()
      instance = Client.new({ 'mock' }, function(client, code, signal)
        exit_args = { client = client, code = code, signal = signal }
      end)
    end)
    feed = function(chunk) stdout_fn(nil, chunk) end
    local init_id = last_sent().id
    feed(ndjson { jsonrpc = '2.0', id = init_id, result = { agentCapabilities = {} } })
    written = {}

    create_session(instance, 'session-1')
    assert.not_equals(nil, instance.sessions['session-1'])

    exit_fn { code = 0, signal = 0 }
    assert.are.same({}, instance.sessions)
    assert.equals(instance, exit_args.client)
    assert.equals(0, exit_args.code)
  end)

  it('chunked delivery works end-to-end', function()
    local instance = new_client()
    local session
    coop.spawn(function()
      session = instance:session_new('/tmp')
    end)
    local message = last_sent()
    local response = ndjson { jsonrpc = '2.0', id = message.id, result = { sessionId = 'x' } }
    local mid = math.floor(#response / 2)
    feed(response:sub(1, mid))
    assert.is_nil(session)
    feed(response:sub(mid + 1))
    assert.equals('x', session.session_id)
  end)

  describe('main-thread freeze regression', function()
    local PAYLOAD_BYTES = 64 * 1024
    local CHUNK_BYTES = 1024
    local BUDGET_MS = 50

    local function big_tool_call_line(session_id, tool_id)
      return ndjson {
        jsonrpc = '2.0',
        method = 'session/update',
        params = {
          sessionId = session_id,
          update = {
            sessionUpdate = 'tool_call',
            toolCallId = tool_id,
            title = 'big',
            kind = 'execute',
            status = 'completed',
            content = {
              {
                type = 'content',
                content = { type = 'text', text = string.rep('x', PAYLOAD_BYTES) },
              },
            },
          },
        },
      }
    end

    it('large tool_call delivered in small chunks stays under budget', function()
      local instance = new_client()
      create_session(instance, 's1')
      local line = big_tool_call_line('s1', 'tc1')
      local total_chunks = math.ceil(#line / CHUNK_BYTES)
      local feed_ns = 0
      local max_chunk_ns = 0

      for offset = 1, #line, CHUNK_BYTES do
        local slice = line:sub(offset, offset + CHUNK_BYTES - 1)
        local start = vim.uv.hrtime()
        feed(slice)
        local elapsed = vim.uv.hrtime() - start
        feed_ns = feed_ns + elapsed
        if elapsed > max_chunk_ns then max_chunk_ns = elapsed end
      end

      local total_ms = feed_ns / 1e6
      local max_chunk_ms = max_chunk_ns / 1e6
      io.stderr:write(string.format(
        '\n[freeze-regression] line=%d bytes  chunks=%d  total=%.1f ms  max_chunk=%.2f ms\n',
        #line, total_chunks, total_ms, max_chunk_ms
      ))
      io.stderr:flush()

      assert.is_true(
        total_ms < BUDGET_MS,
        string.format(
          'feed of %d bytes in %d chunks took %.1f ms (budget %d ms) — main thread frozen that long',
          #line, total_chunks, total_ms, BUDGET_MS
        )
      )
    end)
  end)
end)
