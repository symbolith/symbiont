local coop = require 'coop'

---@param plugin symbiont.Plugin
return function(plugin)
  return function(opts)
    local text = opts.args
    if not text or text == '' then
      vim.notify('symbiont: no text provided', vim.log.levels.WARN)
      return
    end
    coop.spawn(function()
      ---@type symbiont.Session?
      local session = plugin:session():await()
      if not session then return end
      local content = { kind = 'text', text = text }
      session:append_turn { role = 'user', content = { content } }
      session:prompt { content }
    end)
  end
end
