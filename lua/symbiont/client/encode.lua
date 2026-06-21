local M = {}

---@param user_content symbiont.UserContent
---@return acp.ContentBlock
function M.content_block(user_content)
  if user_content.kind == 'text' or user_content.kind == 'thought' then
    return { type = 'text', text = user_content.text }
  elseif user_content.kind == 'image' then
    return { type = 'image', data = user_content.data, mimeType = user_content.mime_type }
  elseif user_content.kind == 'link' then
    return { type = 'resource_link', uri = user_content.uri, name = user_content.name }
  elseif user_content.kind == 'text_resource' then
    return {
      type = 'resource',
      resource = {
        uri = user_content.uri,
        mimeType = user_content.mime_type,
        text = user_content.text,
      },
    }
  elseif user_content.kind == 'blob_resource' then
    return {
      type = 'resource',
      resource = {
        uri = user_content.uri,
        mimeType = user_content.mime_type,
        blob = user_content.blob,
      },
    }
  end
  return { type = 'text', text = '' }
end

return M
