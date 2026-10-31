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

  it('nests tool call bodies (level 2) under the tool call and thinking sections (level 1)', function()
    if not register_symbiont_language() then
      pending('markdown treesitter parser not installed')
      return
    end
    local buffer = Buffer.new()
    buffer:update {
      '#### Thinking', -- 1
      '', -- 2
      '> reasoning one', -- 3
      '> reasoning two', -- 4
      '', -- 5
      '#### Tool Call', -- 6
      '', -- 7
      '- [x] grep "symbiont"', -- 8
      '', -- 9
      '  > Found 37 files', -- 10
      '  > a.lua', -- 11
      '- [x] read bar.lua bar.lua:10', -- 12
    }
    vim.api.nvim_set_current_buf(buffer.bufnr)
    vim.treesitter.get_parser(buffer.bufnr, 'symbiont'):parse()

    -- level 1: the two sections
    assert.equals('>1', vim.treesitter.foldexpr(1)) -- thinking section
    assert.equals('>1', vim.treesitter.foldexpr(6)) -- tool call section
    -- thinking body stays at level 1: reasoning is rendered separately by the client
    assert.equals('1', vim.treesitter.foldexpr(3))
    assert.equals('1', vim.treesitter.foldexpr(4))
    -- tool call title stays at level 1, visible above its folded body
    assert.equals('1', vim.treesitter.foldexpr(8))
    -- level 2: only the tool call body
    assert.equals('>2', vim.treesitter.foldexpr(10))
    assert.equals('2', vim.treesitter.foldexpr(11))
    -- a location-only tool call has no body, so no second-level fold
    assert.equals('1', vim.treesitter.foldexpr(12))
  end)

  describe('update', function()
    it('replaces the buffer contents', function()
      local buffer = Buffer.new()
      buffer:update { 'a', 'b', 'c' }
      assert.same({ 'a', 'b', 'c' }, vim.api.nvim_buf_get_lines(buffer.bufnr, 0, -1, false))
    end)

    it('leaves earlier lines untouched when appending', function()
      local namespace = vim.api.nvim_create_namespace('symbiont_buffer_append')
      local buffer = Buffer.new()
      buffer:update { 'a', 'b', 'c' }
      local mark = vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, 1, 0, {})
      buffer:update { 'a', 'b', 'c', 'd' }
      assert.same({ 1, 0 }, vim.api.nvim_buf_get_extmark_by_id(buffer.bufnr, namespace, mark, {}))
      assert.same({ 'a', 'b', 'c', 'd' }, vim.api.nvim_buf_get_lines(buffer.bufnr, 0, -1, false))
    end)

    it('rewrites only the changed line, leaving surrounding lines untouched', function()
      local namespace = vim.api.nvim_create_namespace('symbiont_buffer_middle')
      local buffer = Buffer.new()
      buffer:update { 'a', 'b', 'c', 'd' }
      local head = vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, 0, 0, {})
      local tail = vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, 3, 0, {})
      buffer:update { 'a', 'X', 'c', 'd' }
      assert.same({ 0, 0 }, vim.api.nvim_buf_get_extmark_by_id(buffer.bufnr, namespace, head, {}))
      assert.same({ 3, 0 }, vim.api.nvim_buf_get_extmark_by_id(buffer.bufnr, namespace, tail, {}))
      assert.same({ 'a', 'X', 'c', 'd' }, vim.api.nvim_buf_get_lines(buffer.bufnr, 0, -1, false))
    end)

    it('keeps a closed fold closed when later lines change', function()
      local buffer = Buffer.new()
      buffer:update { 'head', 'a', 'b', 'c', 'tail' }
      local window = vim.api.nvim_open_win(buffer.bufnr, true, {
        relative = 'editor',
        width = 40,
        height = 10,
        row = 0,
        col = 0,
      })
      vim.wo[window].foldmethod = 'manual'
      vim.api.nvim_win_call(window, function()
        vim.cmd '2,4fold'
      end)
      local closed_before = vim.api.nvim_win_call(window, function()
        return vim.fn.foldclosed(2)
      end)
      buffer:update { 'head', 'a', 'b', 'c', 'tail', 'more' }
      local closed_after = vim.api.nvim_win_call(window, function()
        return vim.fn.foldclosed(2)
      end)
      vim.api.nvim_win_close(window, true)
      assert.equals(2, closed_before)
      assert.equals(2, closed_after)
    end)
  end)
end)
