local config = require 'symbiont.config'

local M = {}

local function find_window()
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'symbiont' then
      return window
    end
  end
end

function M.new()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = 'symbiont'

  local self = { bufnr = bufnr }

  function self:show()
    local window = find_window() or config.create_window()
    vim.api.nvim_win_set_buf(window, bufnr)
    vim.api.nvim_set_current_win(window)
  end

  ---@param lines string[]
  function self:set_lines(lines)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  ---Patches only the lines that changed, so Neovim recomputes folds for the
  ---affected lines and reuses the fold state of every other line (see
  ---|fold-expr-slow|). A full rewrite would reset all folds.
  ---@param lines string[]
  function self:update(lines)
    local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local hunks = vim.text.diff(
      table.concat(current, '\n') .. '\n',
      table.concat(lines, '\n') .. '\n',
      { result_type = 'indices' }
    ) --[[@as integer[][] ]]
    for index = #hunks, 1, -1 do
      local start_old, count_old, start_new, count_new =
        hunks[index][1], hunks[index][2], hunks[index][3], hunks[index][4]
      local first = count_old > 0 and start_old - 1 or start_old
      local replacement = vim.list_slice(lines, start_new, start_new + count_new - 1)
      vim.api.nvim_buf_set_lines(bufnr, first, first + count_old, false, replacement)
    end
  end

  function self:clear()
    self:set_lines {}
  end

  return self
end

return M
