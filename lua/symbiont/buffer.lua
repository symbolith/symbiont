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
  ---@return integer start_line
  ---@return integer end_line
  function self:append_lines(lines)
    local start_line = vim.api.nvim_buf_line_count(bufnr)
    if start_line == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == '' then
      start_line = 0
    end
    vim.api.nvim_buf_set_lines(bufnr, start_line, start_line, false, lines)
    return start_line, start_line + #lines - 1
  end

  ---@param start_line integer
  ---@param end_line integer
  ---@param lines string[]
  ---@return integer new_end_line
  function self:replace_lines(start_line, end_line, lines)
    vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, lines)
    return start_line + #lines - 1
  end

  ---@param start_line integer
  ---@param end_line integer
  function self:delete_lines(start_line, end_line)
    vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, {})
  end

  ---@param lines string[]
  function self:set_lines(lines)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  function self:clear()
    self:set_lines {}
  end

  ---@return integer
  function self:line_count()
    return vim.api.nvim_buf_line_count(bufnr)
  end

  return self
end

return M
