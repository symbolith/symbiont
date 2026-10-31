pcall(vim.treesitter.start)

vim.api.nvim_create_autocmd('BufWinEnter', {
  buffer = vim.api.nvim_get_current_buf(),
  callback = function()
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.opt_local.foldlevel = 0
  end,
})
