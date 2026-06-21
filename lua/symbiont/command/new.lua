local coop = require 'coop'

---@param plugin symbiont.Plugin
return function(plugin)
  return function()
    coop.spawn(function()
      ---@type symbiont.Session?
      local session = plugin:new_session():await()
      if session then session:show() end
    end)
  end
end
