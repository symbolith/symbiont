local markdown_parser = vim.api.nvim_get_runtime_file('parser/markdown.*', false)[1]
if markdown_parser then
  vim.treesitter.language.add('symbiont', {
    path = markdown_parser,
    symbol_name = 'markdown',
  })
end

local symbiont = require 'symbiont'
local commands = symbiont.commands

vim.api.nvim_create_user_command('Symbiont', function() commands.toggle() end, {})
vim.api.nvim_create_user_command('SymbiontStop', function() commands.stop() end, {})
vim.api.nvim_create_user_command('SymbiontCancel', function() commands.cancel() end, {})
vim.api.nvim_create_user_command('SymbiontSubmit', function(opts) commands.submit(opts) end, { range = true, nargs = '*' })
vim.api.nvim_create_user_command('SymbiontAppend', function(opts) commands.append(opts) end, { range = true })
vim.api.nvim_create_user_command('SymbiontMode', function(opts) commands.mode(opts) end, { nargs = '?' })
vim.api.nvim_create_user_command('SymbiontPlan', function() commands.plan() end, {})
vim.api.nvim_create_user_command('SymbiontNew', function() commands.new() end, {})
vim.api.nvim_create_user_command('SymbiontSwitch', function() commands.switch() end, {})

vim.keymap.set('n', '<localleader>cc', function() commands.toggle() end, { silent = true, desc = 'Symbiont: toggle session' })
vim.keymap.set('n', '<localleader>cn', function() commands.new() end, { silent = true, desc = 'Symbiont: new session' })
