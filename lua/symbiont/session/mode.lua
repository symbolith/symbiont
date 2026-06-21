---@class symbiont.SessionMode
---@field id string
---@field name string
---@field description? string

local M = {}

---@return symbiont.Mode
function M.new()
  local current_mode_id = nil
  local available_modes = {}

  ---@class symbiont.Mode
  local self = {}

  ---@param mode_id string
  function self:set_current(mode_id)
    current_mode_id = mode_id
  end

  ---@param modes symbiont.SessionMode[]
  function self:set_available(modes)
    available_modes = modes
  end

  ---@return string?
  function self:current()
    return current_mode_id
  end

  ---@return symbiont.SessionMode[]
  function self:available()
    return available_modes
  end

  return self
end

return M
