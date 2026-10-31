local M = {
  agents = {
    { name = 'default', cmd = { 'env', 'MAX_THINKING_TOKENS=8000', 'claude-code-acp' } },
  },
  default_agent = 'default',
  header = {
    user = '### You',
    assistant = '### Agent',
  },
  assistant_message_header = '#### Message',
  tool_call_header = '#### Tool Call',
  thought_header = '#### Thinking',
  permission_header = '#### Permission',
  create_window = function()
    vim.cmd('vsplit')
    return vim.api.nvim_get_current_win()
  end,
}

function M.agent(name)
  name = name or M.default_agent
  for _, agent in ipairs(M.agents) do
    if agent.name == name then return agent end
  end
end

function M.setup(opts)
  opts = opts or {}
  if opts.agents then M.agents = opts.agents end
  if opts.default_agent then M.default_agent = opts.default_agent end
  if opts.create_window then M.create_window = opts.create_window end
  vim.validate('config.agents', M.agents, 'table')
  vim.validate('config.default_agent', M.default_agent, 'string')
  vim.validate('config.create_window', M.create_window, 'function')
  for _, agent in ipairs(M.agents) do
    vim.validate('config.agents[].name', agent.name, 'string')
    vim.validate('config.agents[].cmd', agent.cmd, 'table')
  end
end

return M
