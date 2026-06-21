local Client = require 'symbiont.client'
local coop = require 'coop'
local config = require 'symbiont.config'

local function task_value(task)
  if task and task.future.done and task.future.results[1] then
    return task.future.results[2]
  end
end

---@class symbiont.Plugin
---@field clients table<string, Coop.Task>
---@field _session Coop.Task?
local plugin = {
  clients = {},
  _session = nil,
}

---@param agent_name? string
---@return Coop.Task
function plugin:create_client(agent_name)
  local agent = config.agent(agent_name)
  if not self.clients[agent.name] then
    self.clients[agent.name] = coop.spawn(function()
      local client, init_error = Client.new(agent.cmd, function(c, code, signal)
        self:on_client_exit(c, code, signal)
      end)
      if not client then error('symbiont: ' .. init_error, 0) end
      return client
    end)
  end
  return self.clients[agent.name]
end

---@return Coop.Task
function plugin:session()
  if not self._session then
    self._session = coop.spawn(function()
      local ok, session = pcall(function()
        return self:create_client():await():session_new(vim.fn.getcwd())
      end)
      if not ok then
        self._session = nil
        vim.notify('symbiont: ' .. tostring(session), vim.log.levels.ERROR)
        return nil
      end
      return session
    end)
  end
  return self._session
end

---@return Coop.Task
function plugin:new_session()
  self._session = nil
  return self:session()
end

---@param exited_client symbiont.Client
---@param code integer
---@param signal integer
function plugin:on_client_exit(exited_client, code, signal)
  for name, task in pairs(self.clients) do
    if task_value(task) == exited_client then
      self.clients[name] = nil
      break
    end
  end
  local session = task_value(self._session)
  if session and exited_client.sessions[session.session_id] then
    self._session = nil
  end
  vim.notify(
    ('symbiont: agent exited (code=%d, signal=%d)'):format(code, signal),
    vim.log.levels.INFO
  )
end

return { commands = require 'symbiont.command'(plugin) }
