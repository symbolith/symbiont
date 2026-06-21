---@alias symbiont.rpc.Message
---| symbiont.rpc.Request
---| symbiont.rpc.Notification
---| symbiont.rpc.Response

---@class symbiont.rpc.Request
---@field jsonrpc string
---@field id integer
---@field method string
---@field params? table

---@class symbiont.rpc.Notification
---@field jsonrpc string
---@field method string
---@field params? table

---@alias symbiont.rpc.Response
---| symbiont.rpc.SuccessResponse
---| symbiont.rpc.ErrorResponse

---@class symbiont.rpc.SuccessResponse
---@field jsonrpc string
---@field id integer
---@field result acp.Result

---@class symbiont.rpc.ErrorResponse
---@field jsonrpc string
---@field id integer
---@field error symbiont.rpc.Error

---@class symbiont.rpc.Error
---@field code integer
---@field message string

local M = {}

---@param message symbiont.rpc.Message
---@return string
function M.encode(message)
  return vim.json.encode(message) .. '\n'
end

---@return fun(chunk: string): symbiont.rpc.Message[], string[]
function M.decoder()
  local pending = {}
  return function(chunk)
    local messages, errors = {}, {}
    local cursor = 1
    local newline = chunk:find('\n', cursor, true)
    while newline do
      pending[#pending + 1] = chunk:sub(cursor, newline - 1)
      local line = table.concat(pending)
      pending = {}
      local ok, decoded = pcall(vim.json.decode, line)
      if ok then
        messages[#messages + 1] = decoded
      else
        errors[#errors + 1] = decoded
      end
      cursor = newline + 1
      newline = chunk:find('\n', cursor, true)
    end
    if cursor <= #chunk then
      pending[#pending + 1] = chunk:sub(cursor)
    end
    return messages, errors
  end
end

return M
