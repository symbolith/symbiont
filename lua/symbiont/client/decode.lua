local M = {}

---@param content_block acp.ContentBlock
---@return symbiont.UserContent
function M.content_block(content_block)
  if content_block.type == 'text' then
    return { kind = 'text', text = content_block.text }
  elseif content_block.type == 'image' then
    return { kind = 'image', data = content_block.data, mime_type = content_block.mimeType }
  elseif content_block.type == 'resource_link' then
    return { kind = 'link', uri = content_block.uri, name = content_block.name }
  elseif content_block.type == 'resource' then
    if content_block.resource.blob ~= nil then
      return {
        kind = 'blob_resource',
        uri = content_block.resource.uri,
        mime_type = content_block.resource.mimeType,
        blob = content_block.resource.blob,
      }
    end
    return {
      kind = 'text_resource',
      uri = content_block.resource.uri,
      mime_type = content_block.resource.mimeType,
      text = content_block.resource.text,
    }
  end
  error(('symbiont: unknown content block type: %s'):format(tostring(content_block.type)))
end

---@param tool_call_content acp.ToolCallContent
---@return symbiont.ToolCallContent
local function tool_content(tool_call_content)
  if tool_call_content.type == 'content' then
    return M.content_block(tool_call_content.content)
  elseif tool_call_content.type == 'diff' then
    return {
      kind = 'diff',
      path = tool_call_content.path,
      new_text = tool_call_content.newText,
      old_text = tool_call_content.oldText,
    }
  end
  error(('symbiont: unknown tool call content type: %s'):format(tostring((tool_call_content --[[@as any]]).type)))
end

---@param update { content: acp.ContentBlock }
---@return symbiont.UserTurn
function M.user_turn(update)
  return { role = 'user', content = { M.content_block(update.content) } }
end

---@param update { content: acp.ContentBlock }
---@return symbiont.AssistantTurn
function M.agent_turn(update)
  return { role = 'assistant', content = { M.content_block(update.content) } }
end

---@param content_block acp.ContentBlock
---@return symbiont.Thought
function M.agent_thought_chunk(content_block)
  return { kind = 'thought', content = { M.content_block(content_block) } }
end

---@param tool_call_contents acp.ToolCallContent[]?
---@return symbiont.ToolCallContent[]?
function M.tool_contents(tool_call_contents)
  if not tool_call_contents then
    return nil
  end
  local result = {}
  for _, tool_call_content in ipairs(tool_call_contents) do
    result[#result + 1] = tool_content(tool_call_content)
  end
  return result
end

---@param tool_call acp.ToolCall | acp.ToolCallUpdate
---@return symbiont.ToolCall
local function tool_call_block(tool_call)
  return {
    kind = 'tool_call',
    id = tool_call.toolCallId,
    title = tool_call.title,
    tool_kind = tool_call.kind,
    status = tool_call.status,
    locations = tool_call.locations --[[@as symbiont.FileLocation[]? ]],
    content = M.tool_contents(tool_call.content),
  }
end

M.tool_call = tool_call_block
M.tool_call_update = tool_call_block

---@param entries acp.PlanEntry[]
---@return symbiont.PlanEntry[]
function M.plan_entries(entries)
  return entries --[[@as symbiont.PlanEntry[] ]]
end

---@param options acp.PermissionOption[]
---@return symbiont.PermissionOption[]
local function permission_options(options)
  local result = {}
  for position, option in ipairs(options) do
    result[position] = { id = option.optionId, name = option.name, kind = option.kind }
  end
  return result
end

---@param request_id integer
---@param params acp.PermissionRequestParams
---@return symbiont.PermissionRequest
function M.permission_request(request_id, params)
  return {
    request_id = request_id,
    tool_id = params.toolCall.toolCallId,
    tool_title = params.toolCall.title,
    options = permission_options(params.options),
  }
end

return M
