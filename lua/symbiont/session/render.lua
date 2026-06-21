local config = require 'symbiont.config'

local map = vim.tbl_map

local M = {}

local TOOL_STATUS_CHECKBOX = {
  pending = '[ ]',
  in_progress = '[/]',
  completed = '[x]',
  failed = '[!]',
}

local TOOL_KIND_ICON = {
  read = '📖',
  edit = '✏️',
  delete = '🗑️',
  move = '📦',
  search = '🔍',
  execute = '▶️',
  think = '💭',
  fetch = '🌐',
  switch_mode = '🔄',
  other = '🔧',
}

---@param lists string[][]
---@return string[]
local function flatten(lists)
  return vim.iter(lists):flatten():totable()
end

---@param lists string[][]
---@param separator string
---@return string[]
local function flatten_with(lists, separator)
  local out = {}
  for index, list in ipairs(lists) do
    if index > 1 then
      out[#out + 1] = separator
    end
    vim.list_extend(out, list)
  end
  return out
end

---@generic T, K
---@param items T[]
---@param key fun(item: T): K
---@return { key: K, items: T[] }[]
local function chunk_by(items, key)
  return vim.iter(items):fold({}, function(acc, item)
    local last = acc[#acc]
    local current_key = key(item)
    if last and last.key == current_key then
      last.items[#last.items + 1] = item
    else
      acc[#acc + 1] = { key = current_key, items = { item } }
    end
    return acc
  end)
end

---@generic T
---@param fn fun(item: T): string[]
---@param items T[]
---@param separator string
---@return string[]
local function flat_map_with(fn, items, separator)
  return flatten_with(map(fn, items), separator)
end

---@generic T
---@param fn fun(item: T): string[]
---@param items T[]
---@return string[]
local function flat_map(fn, items)
  return flat_map_with(fn, items, '')
end

---@param lines string[]
---@param prefix string
---@return string[]
local function prefix_lines(lines, prefix)
  return map(function(line)
    return prefix .. line
  end, lines)
end

---@param lines string[]
---@param language? string
---@return string[]
local function fence_lines(lines, language)
  return flatten {
    { '```' .. (language or '') },
    lines,
    { '```' },
  }
end

---@param target string
---@param base string
---@return string
local function relativize(target, base)
  if not target:match '^/' then
    return target
  end
  local up = ''
  while base ~= '' and target:sub(1, #base + 1) ~= base .. '/' do
    up = up .. '../'
    base = base:match '(.*)/' or ''
  end
  return up .. target:sub(#base + 2)
end

---@param file_location symbiont.FileLocation
---@param cwd string
---@return string
local function render_file_location(file_location, cwd)
  local path = relativize(file_location.path, cwd)
  if file_location.line then
    return ('%s:%d'):format(path, file_location.line)
  end
  return path
end

---@param text symbiont.Text
---@return string[]
local function render_text(text)
  return vim.split(text.text, '\n', { plain = true })
end

---@param image symbiont.Image
---@return string[]
local function render_image(image)
  return { ('[%s](%s)'):format(image.mime_type, image.data) }
end

---@param link symbiont.Link
---@return string[]
local function render_link(link)
  return { ('[%s](%s)'):format(link.name, link.uri) }
end

---@param resource symbiont.TextResource
---@return string[]
local function render_text_resource(resource)
  return fence_lines(vim.split(resource.text, '\n', { plain = true }), resource.mime_type)
end

---@param resource symbiont.BlobResource
---@return string[]
local function render_blob_resource(resource)
  return { ('[%s]'):format(resource.uri) }
end

---@param diff symbiont.Diff
---@return string[]
local function render_diff(diff)
  local body = (diff.old_text or '') .. diff.new_text
  return fence_lines(vim.split(body, '\n', { plain = true }), 'diff')
end

---@type fun(content: symbiont.Content, cwd: string): string[]
local render_content

---@param contents symbiont.Content[]
---@param cwd string
---@return string[]
local function render_contents(contents, cwd)
  return flat_map(function(content)
    return render_content(content, cwd)
  end, contents)
end

---@param thought symbiont.Thought
---@param cwd string
---@return string[]
local function render_thought(thought, cwd)
  local body = prefix_lines(render_contents(thought.content or {}, cwd), '> ')
  return flatten { { config.thought_header, '' }, body }
end

---@param tool_call symbiont.ToolCall
---@param cwd string
---@return string
local function render_tool_call_title(tool_call, cwd)
  local parts = {
    '-',
    TOOL_STATUS_CHECKBOX[tool_call.status] or '',
    TOOL_KIND_ICON[tool_call.tool_kind] or '',
    tool_call.title,
  }
  if tool_call.locations and #tool_call.locations > 0 then
    parts[#parts + 1] = table.concat(
      map(function(file_location)
        return render_file_location(file_location, cwd)
      end, tool_call.locations),
      ', '
    )
  end
  return table.concat(parts, ' ')
end

---@param tool_call_content symbiont.ToolCallContent
---@param cwd string
---@return string[]
local function render_tool_call_content(tool_call_content, cwd)
  local lines = render_content(tool_call_content, cwd)
  if tool_call_content.kind == 'text' then
    return prefix_lines(lines, '> ')
  end
  return lines
end

---@param tool_call symbiont.ToolCall
---@param cwd string
---@return string[]
local function render_tool_call_body(tool_call, cwd)
  if tool_call.locations and #tool_call.locations > 0 then
    return {}
  end
  return flat_map(function(tool_call_content)
    return render_tool_call_content(tool_call_content, cwd)
  end, tool_call.content or {})
end

---@param tool_call symbiont.ToolCall
---@param cwd string
---@return string[]
local function render_tool_call(tool_call, cwd)
  local title = render_tool_call_title(tool_call, cwd)
  local body = render_tool_call_body(tool_call, cwd)
  if #body == 0 then
    return { title }
  end
  return flatten { { title, '' }, prefix_lines(body, '  ') }
end

render_content = function(content, cwd)
  if content.kind == 'tool_call' then
    return render_tool_call(content, cwd)
  end
  if content.kind == 'thought' then
    return render_thought(content, cwd)
  end
  if content.kind == 'text' then
    return render_text(content)
  end
  if content.kind == 'image' then
    return render_image(content)
  end
  if content.kind == 'link' then
    return render_link(content)
  end
  if content.kind == 'text_resource' then
    return render_text_resource(content)
  end
  if content.kind == 'blob_resource' then
    return render_blob_resource(content)
  end
  if content.kind == 'diff' then
    return render_diff(content)
  end
  return {}
end

---@param assistant_content symbiont.AssistantContent
---@return boolean
local function is_tool_call(assistant_content)
  return assistant_content.kind == 'tool_call'
end

---@param tool_calls symbiont.ToolCall[]
---@param cwd string
---@return string[]
local function render_tool_calls(tool_calls, cwd)
  local rendered = map(function(tool_call)
    return render_tool_call(tool_call, cwd)
  end, tool_calls)
  local units = map(
    function(group)
      return group.key and flatten(group.items) or flatten_with(group.items, '')
    end,
    chunk_by(rendered, function(lines)
      return #lines == 1
    end)
  )
  return flatten { { config.tool_call_header, '' }, flatten_with(units, '') }
end

---@param assistant_contents symbiont.AssistantContent[]
---@param cwd string
---@return string[]
local function render_assistant_contents(assistant_contents, cwd)
  return flat_map(function(group)
    return group.key and render_tool_calls(group.items, cwd) or render_contents(group.items, cwd)
  end, chunk_by(assistant_contents, is_tool_call))
end

---@param turn symbiont.Turn
---@param cwd string
---@return string[]
local function render_turn(turn, cwd)
  local body = turn.role == 'assistant' and render_assistant_contents(turn.content, cwd)
    or render_contents(turn.content, cwd)
  return flatten { { config.header[turn.role], '' }, body }
end

---@param turns symbiont.Turn[]
---@param cwd string
---@return string[]
local function render_turns(turns, cwd)
  return flat_map(function(turn)
    return render_turn(turn, cwd)
  end, turns)
end

---@param conversation symbiont.Conversation
---@param cwd string
---@return string[]
function M.conversation(conversation, cwd)
  return flatten { render_turns(conversation.turns, cwd), { '' } }
end

return M
