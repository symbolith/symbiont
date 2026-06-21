---@class symbiont.Conversation
---@field turns symbiont.Turn[]

---@alias symbiont.Turn symbiont.UserTurn | symbiont.AssistantTurn

---@class symbiont.UserTurn
---@field role 'user'
---@field content symbiont.UserContent[]

---@alias symbiont.UserContent
---| symbiont.Text
---| symbiont.Image
---| symbiont.Link
---| symbiont.TextResource
---| symbiont.BlobResource

---@class symbiont.AssistantTurn
---@field role 'assistant'
---@field content symbiont.AssistantContent[]

---@alias symbiont.AssistantContent
---| symbiont.ToolCall
---| symbiont.Thought
---| symbiont.Text
---| symbiont.Image
---| symbiont.Link
---| symbiont.TextResource
---| symbiont.BlobResource

---@alias symbiont.Content
---| symbiont.Text
---| symbiont.Image
---| symbiont.Diff
---| symbiont.Link
---| symbiont.TextResource
---| symbiont.BlobResource
---| symbiont.ToolCall
---| symbiont.Thought

---@class symbiont.ToolCall
---@field kind 'tool_call'
---@field id string
---@field title? string
---@field tool_kind? symbiont.ToolKind
---@field status? symbiont.ToolStatus
---@field locations? symbiont.FileLocation[]
---@field content? symbiont.ToolCallContent[]

---@alias symbiont.ToolCallContent
---| symbiont.Text
---| symbiont.Image
---| symbiont.Link
---| symbiont.TextResource
---| symbiont.BlobResource
---| symbiont.Diff

---@class symbiont.Thought
---@field kind 'thought'
---@field content symbiont.ThoughtContent[]

---@alias symbiont.ThoughtContent
---| symbiont.Text
---| symbiont.Image
---| symbiont.Link
---| symbiont.TextResource
---| symbiont.BlobResource

---@alias symbiont.ToolKind 'read'|'edit'|'delete'|'move'|'search'|'execute'|'think'|'fetch'|'switch_mode'|'other'
---@alias symbiont.ToolStatus 'pending'|'in_progress'|'completed'|'failed'

---@class symbiont.FileLocation
---@field path string
---@field line? integer

---@class symbiont.Text
---@field kind 'text'
---@field text string

---@class symbiont.Image
---@field kind 'image'
---@field data string
---@field mime_type string

---@class symbiont.Link
---@field kind 'link'
---@field uri string
---@field name string

---@class symbiont.TextResource
---@field kind 'text_resource'
---@field uri string
---@field mime_type? string
---@field text string

---@class symbiont.BlobResource
---@field kind 'blob_resource'
---@field uri string
---@field mime_type? string
---@field blob string

---@class symbiont.Diff
---@field kind 'diff'
---@field path string
---@field new_text string
---@field old_text? string

local M = {}

---@return symbiont.Conversation
function M.new()
  ---@class symbiont.Conversation
  local self = { turns = {} }
  local tool_index = {}

  ---@param role 'user'|'assistant'
  ---@return symbiont.Turn
  local function open_turn(role)
    local last = self.turns[#self.turns]
    if last and last.role == role then
      return last
    end
    last = { role = role, content = {} }
    self.turns[#self.turns + 1] = last
    return last
  end

  ---@param content_list symbiont.Content[]
  ---@param incoming symbiont.Content
  local function push_or_merge_text(content_list, incoming)
    local previous = content_list[#content_list]
    if previous and previous.kind == 'text' and incoming.kind == 'text' then
      previous.text = previous.text .. incoming.text
    else
      content_list[#content_list + 1] = incoming
    end
  end

  ---@param existing symbiont.ToolCall
  ---@param incoming symbiont.ToolCall
  local function merge_tool_call(existing, incoming)
    if incoming.title ~= nil then
      existing.title = incoming.title
    end
    if incoming.tool_kind ~= nil then
      existing.tool_kind = incoming.tool_kind
    end
    if incoming.status ~= nil then
      existing.status = incoming.status
    end
    if incoming.locations ~= nil then
      existing.locations = incoming.locations
    end
    if incoming.content ~= nil then
      existing.content = incoming.content
    end
  end

  ---@param turn symbiont.Turn
  function self:append_turn(turn)
    local target = open_turn(turn.role).content
    for _, content in ipairs(turn.content) do
      push_or_merge_text(target, content)
    end
  end

  ---@param thought symbiont.Thought
  function self:add_thought(thought)
    local target = open_turn('assistant').content
    local previous = target[#target]
    if previous and previous.kind == 'thought' then
      for _, chunk in ipairs(thought.content) do
        push_or_merge_text(previous.content, chunk)
      end
      return
    end
    target[#target + 1] = thought
  end

  ---@param tool_call symbiont.ToolCall
  function self:add_tool_call(tool_call)
    local existing = tool_index[tool_call.id]
    if existing then
      merge_tool_call(existing, tool_call)
      return
    end
    local target = open_turn('assistant').content
    target[#target + 1] = tool_call
    tool_index[tool_call.id] = tool_call
  end

  ---@param tool_call symbiont.ToolCall
  function self:update_tool_call(tool_call)
    local existing = tool_index[tool_call.id]
    if existing then
      merge_tool_call(existing, tool_call)
    end
  end

  ---@param tool_id string
  ---@return symbiont.ToolCall?
  function self:get_tool(tool_id)
    return tool_index[tool_id]
  end

  return self
end

return M
