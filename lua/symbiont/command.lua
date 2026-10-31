---@param plugin symbiont.Plugin
return function(plugin)
  return {
    setup = require 'symbiont.command.setup'(plugin),
    toggle = require 'symbiont.command.toggle'(plugin),
    stop = require 'symbiont.command.stop'(plugin),
    cancel = require 'symbiont.command.cancel'(plugin),
    submit = require 'symbiont.command.submit'(plugin),
    append = require 'symbiont.command.append'(plugin),
    mode = require 'symbiont.command.mode'(plugin),
    plan = require 'symbiont.command.plan'(plugin),
    new = require 'symbiont.command.new'(plugin),
    switch = require 'symbiont.command.switch'(plugin),
  }
end
