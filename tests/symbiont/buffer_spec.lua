local Buffer = require 'symbiont.buffer'

local function find_new_buffer(before)
  local after = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(after) do
    if not vim.tbl_contains(before, bufnr) then
      return bufnr
    end
  end
end

local function register_symbiont_language()
  local markdown_parser = vim.api.nvim_get_runtime_file('parser/markdown.*', false)[1]
  if not markdown_parser then return false end
  return pcall(vim.treesitter.language.add, 'symbiont', {
    path = markdown_parser,
    symbol_name = 'markdown',
  })
end

describe('buffer', function()
  before_each(function()
    register_symbiont_language()
  end)

  it('registers symbiont as its own treesitter language backed by the markdown parser', function()
    assert.equals(true, pcall(vim.treesitter.language.inspect, 'symbiont'))
  end)

  it('sets filetype to symbiont', function()
    local before = vim.api.nvim_list_bufs()
    Buffer.new()
    local bufnr = find_new_buffer(before)
    assert.not_equals(nil, bufnr)
    assert.equals('symbiont', vim.bo[bufnr].filetype)
  end)

  it('starts treesitter highlighting when the markdown parser is available', function()
    if not register_symbiont_language() then
      pending('markdown treesitter parser not installed')
      return
    end
    local before = vim.api.nvim_list_bufs()
    Buffer.new()
    local bufnr = find_new_buffer(before)
    assert.not_equals(nil, bufnr)
    assert.not_equals(nil, vim.treesitter.highlighter.active[bufnr])
  end)
end)
