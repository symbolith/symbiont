local config = require 'symbiont.config'

---@param plugin symbiont.Plugin
return function(plugin)
  return function(opts)
    config.setup(opts)
  end
end
