local Conversation = require 'symbiont.session.conversation'
local Plan = require 'symbiont.session.plan'
local Mode = require 'symbiont.session.mode'
local Buffer = require 'symbiont.buffer'
local render = require 'symbiont.session.render'
local coop_task = require 'coop.task'

---@alias symbiont.PermissionOptionKind 'allow_once'|'allow_always'|'reject_once'|'reject_always'

---@class symbiont.PermissionOption
---@field id string
---@field name string
---@field kind symbiont.PermissionOptionKind

---@class symbiont.PermissionRequest
---@field request_id integer
---@field tool_id string
---@field tool_title? string
---@field options symbiont.PermissionOption[]

local M = {}

---@param session_id string
---@param client symbiont.Client
---@param cwd string
---@return symbiont.Session
function M.new(session_id, client, cwd)
  local conversation = Conversation.new()
  local plan = Plan.new()
  local mode = Mode.new()
  local buffer = Buffer.new()
  ---@type symbiont.PermissionRequest?
  local permission = nil

  local refresh_pending = false
  local function refresh()
    if refresh_pending then
      return
    end
    refresh_pending = true
    vim.schedule(function()
      refresh_pending = false
      buffer:update(render.conversation(conversation, cwd))
    end)
  end

  ---@class symbiont.Session
  ---@field session_id string
  local self = { session_id = session_id }

  function self:initialize()
    self:append_turn { role = 'user', content = {} }
  end

  function self:show()
    buffer:show()
  end

  ---@param turn symbiont.Turn
  function self:append_turn(turn)
    conversation:append_turn(turn)
    refresh()
  end

  ---@param thought symbiont.Thought
  function self:add_thought(thought)
    conversation:add_thought(thought)
    refresh()
  end

  ---@param tool_call symbiont.ToolCall
  function self:add_tool_call(tool_call)
    conversation:add_tool_call(tool_call)
    refresh()
  end

  ---@param tool_call symbiont.ToolCall
  function self:update_tool_call(tool_call)
    conversation:update_tool_call(tool_call)
    refresh()
  end

  ---@param tool_id string
  ---@return symbiont.ToolCall?
  function self:get_tool(tool_id)
    return conversation:get_tool(tool_id)
  end

  ---@param permission_request symbiont.PermissionRequest
  function self:set_permission(permission_request)
    permission = permission_request
    refresh()
  end

  function self:resolve_permission()
    permission = nil
    refresh()
  end

  ---@param plan_entries symbiont.PlanEntry[]
  function self:set_plan(plan_entries)
    plan:update(plan_entries)
  end

  ---@param mode_id string
  function self:set_mode(mode_id)
    mode:set_current(mode_id)
  end

  function self:clear()
    conversation = Conversation.new()
    plan = Plan.new()
    mode = Mode.new()
    permission = nil
    buffer:clear()
  end

  ---@param prompt symbiont.UserContent[]
  function self:prompt(prompt)
    client:prompt(session_id, prompt)
  end

  function self:cancel()
    client:cancel(session_id)
  end

  ---@param request_id integer
  ---@param option_id string
  function self:permission_selected(request_id, option_id)
    client:permission_selected(request_id, option_id)
  end

  ---@param request_id integer
  function self:permission_cancelled(request_id)
    client:permission_cancelled(request_id)
  end

  return self
end

return M
