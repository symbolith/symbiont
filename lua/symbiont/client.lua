local coop_task = require 'coop.task'
local rpc = require 'symbiont.client.rpc'
local acp = require 'symbiont.client.acp'
local decode = require 'symbiont.client.decode'
local encode = require 'symbiont.client.encode'
local Session = require 'symbiont.session'

local CLIENT_NAME = 'symbiont.nvim'
local CLIENT_VERSION = '0.0.0'

---@class symbiont.Client
---@field sessions table<string, symbiont.Session>
---@field agent_capabilities acp.AgentCapabilities?
---@field agent_info { name: string, version: string }?
local M = {}

---@async
---@param command string[]
---@param on_exit fun(client: symbiont.Client, code: integer, signal: integer)
---@return symbiont.Client?, string?
function M.new(command, on_exit)
  local pending_requests = {}
  local decode_rpc = rpc.decoder()
  local handle

  ---@class symbiont.Client
  local client = { sessions = {} }

  local next_id = (function()
    local counter = 0
    return function()
      counter = counter + 1
      return counter
    end
  end)()

  local function send(payload)
    local ok, error_value = pcall(handle.write, handle, rpc.encode(payload))
    if not ok then
      vim.notify('symbiont: write failed: ' .. tostring(error_value), vim.log.levels.ERROR)
    end
  end

  ---@async
  local function request(method, payload)
    pending_requests[payload.id] = coop_task.running()
    send(payload)
    local response = coop_task.yield()
    if response.error then
      error(('symbiont: %s failed: %s'):format(method, response.error.message))
    end
    return response.result
  end

  local function handle_response(message)
    local waiting_task = pending_requests[message.id]
    if not waiting_task then
      if message.error then
        vim.notify(('symbiont: %s'):format(message.error.message), vim.log.levels.ERROR)
      end
      return
    end
    pending_requests[message.id] = nil
    coop_task.resume(waiting_task, message)
  end

  ---@param message symbiont.rpc.Notification
  local function handle_notification(message)
    local session = client.sessions[message.params.sessionId]
    if not session then return end
    ---@type string
    local update_type = message.params.update.sessionUpdate
    local update = message.params.update

    if update_type == 'user_message_chunk' then
      session:append_turn(decode.user_turn(update))
    elseif update_type == 'agent_message_chunk' then
      session:append_turn(decode.agent_turn(update))
    elseif update_type == 'agent_thought_chunk' then
      session:add_thought(decode.agent_thought_chunk(update.content))
    elseif update_type == 'tool_call' then
      session:add_tool_call(decode.tool_call(update))
    elseif update_type == 'tool_call_update' then
      session:update_tool_call(decode.tool_call_update(update))
    elseif update_type == 'plan' then
      session:set_plan(decode.plan_entries(update.entries or {}))
    elseif update_type == 'current_mode_update' then
      session:set_mode(update.currentModeId)
    end
  end

  ---@param message symbiont.rpc.Request
  local function handle_request(message)
    ---@cast message { id: integer, params: acp.PermissionRequestParams }
    local session = client.sessions[message.params.sessionId]
    if not session then return end
    session:set_permission(decode.permission_request(message.id, message.params))
  end

  local function dispatch(message)
    vim.schedule(function()
      if message.result ~= nil or message.error ~= nil then
        handle_response(message)
      elseif message.id then
        handle_request(message)
      else
        handle_notification(message)
      end
    end)
  end

  local function on_stdout(chunk)
    if not chunk then return end
    local messages, errors = decode_rpc(chunk)
    for _, message in ipairs(messages) do
      dispatch(message)
    end
    for _, parse_error in ipairs(errors) do
      vim.schedule(function()
        vim.notify('symbiont: ' .. parse_error, vim.log.levels.WARN)
      end)
    end
  end

  local function on_process_exit(result)
    vim.schedule(function()
      local exit_response = { error = { code = -1, message = 'agent exited' } }
      for id, waiting_task in pairs(pending_requests) do
        pending_requests[id] = nil
        coop_task.resume(waiting_task, exit_response)
      end
      client.sessions = {}
      on_exit(client, result.code, result.signal)
    end)
  end

  ---@param session_id string
  ---@param cwd string
  ---@return symbiont.Session
  local function register_session(session_id, cwd)
    local session = Session.new(session_id, client, cwd)
    client.sessions[session_id] = session
    return session
  end

  function client:close()
    handle:kill()
  end

  ---@async
  ---@param cwd? string
  ---@return acp.ListSessionsResult
  function client:session_list(cwd)
    return request('session_list', acp.ListSessionsRequest(next_id(), cwd))
  end

  ---@async
  ---@param cwd string
  ---@return symbiont.Session
  function client:session_new(cwd)
    local result = request('session_new', acp.NewSessionRequest(next_id(), cwd))
    local session = register_session(result.sessionId, cwd)
    session:initialize()
    return session
  end

  ---@async
  ---@param session_id string
  ---@param cwd string
  ---@return symbiont.Session
  function client:session_load(session_id, cwd)
    local session = register_session(session_id, cwd)
    local ok, request_error = pcall(request, 'session_load', acp.LoadSessionRequest(next_id(), session_id, cwd))
    if not ok then
      client.sessions[session_id] = nil
      error(request_error)
    end
    session:initialize()
    return session
  end

  ---@param session_id string
  ---@param prompt symbiont.UserContent[]
  function client:prompt(session_id, prompt)
    local content_blocks = {}
    for index, user_content in ipairs(prompt) do
      content_blocks[index] = encode.content_block(user_content)
    end
    send(acp.PromptRequest(next_id(), session_id, content_blocks))
  end

  ---@param session_id string
  ---@param mode_id string
  function client:set_mode(session_id, mode_id)
    send(acp.SetModeRequest(next_id(), session_id, mode_id))
  end

  ---@param session_id string
  ---@param config_option_id string
  ---@param value string
  function client:set_config_option(session_id, config_option_id, value)
    send(acp.SetConfigOptionRequest(next_id(), session_id, config_option_id, value))
  end

  ---@param session_id string
  function client:cancel(session_id)
    send(acp.CancelNotification(session_id))
  end

  ---@param request_id integer
  ---@param option_id string
  function client:permission_selected(request_id, option_id)
    send(acp.PermissionSelectedResponse(request_id, option_id))
  end

  ---@param request_id integer
  function client:permission_cancelled(request_id)
    send(acp.PermissionCancelledResponse(request_id))
  end

  local spawn_ok, spawn_error = pcall(function()
    handle = vim.system(command, {
      stdin = true,
      stdout = function(_, chunk) on_stdout(chunk) end,
    }, function(process_result) on_process_exit(process_result) end)
  end)
  if not spawn_ok then
    return nil, tostring(spawn_error)
  end

  local init_ok, result = pcall(request, 'initialize', acp.InitializeRequest(next_id(), CLIENT_NAME, CLIENT_VERSION))
  if not init_ok then
    handle:kill()
    return nil, tostring(result)
  end

  client.agent_capabilities = result.agentCapabilities
  client.agent_info = result.agentInfo

  return client
end

return M
