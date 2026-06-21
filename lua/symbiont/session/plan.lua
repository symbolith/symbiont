---@alias symbiont.PlanEntryPriority 'high'|'medium'|'low'
---@alias symbiont.PlanEntryStatus 'pending'|'in_progress'|'completed'

---@class symbiont.PlanEntry
---@field content string
---@field priority symbiont.PlanEntryPriority
---@field status symbiont.PlanEntryStatus

local M = {}

local PLAN_ENTRY_STATUS_ICON = {
  pending = '☐',
  in_progress = '◐',
  completed = '☑',
}

---@param entries symbiont.PlanEntry[]
---@param header string
---@return string[]
function M.render(entries, header)
  local lines = { header, '' }
  for _, entry in ipairs(entries) do
    local status_icon = PLAN_ENTRY_STATUS_ICON[entry.status] or ''
    lines[#lines + 1] = ('- %s [%s] %s'):format(status_icon, entry.priority, entry.content)
  end
  lines[#lines + 1] = ''
  return lines
end

---@return symbiont.Plan
function M.new()
  local entries = {}

  ---@class symbiont.Plan
  local self = {}

  ---@param plan_entries symbiont.PlanEntry[]
  function self:update(plan_entries)
    entries = plan_entries
  end

  ---@return symbiont.PlanEntry[]
  function self:get_entries()
    return entries
  end

  return self
end

return M
