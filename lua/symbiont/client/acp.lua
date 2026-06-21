---@alias acp.ContentBlock
---| acp.TextContent
---| acp.ImageContent
---| acp.AudioContent
---| acp.ResourceLink
---| acp.EmbeddedResource

---@class acp.ContentChunk
---@field content acp.ContentBlock

---@class acp.TextContent
---@field type 'text'
---@field text string

---@class acp.ImageContent
---@field type 'image'
---@field data string
---@field mimeType string

---@class acp.AudioContent
---@field type 'audio'
---@field data string
---@field mimeType string

---@class acp.ResourceLink
---@field type 'resource_link'
---@field uri string
---@field name string

---@class acp.EmbeddedResource
---@field type 'resource'
---@field resource acp.EmbeddedResourceContents

---@alias acp.EmbeddedResourceContents acp.TextResourceContents|acp.BlobResourceContents

---@class acp.TextResourceContents
---@field uri string
---@field mimeType? string
---@field text string

---@class acp.BlobResourceContents
---@field uri string
---@field mimeType? string
---@field blob string

---@class acp.SessionInfo
---@field sessionId string
---@field cwd string
---@field title? string
---@field updatedAt? string

---@class acp.SessionModeState
---@field currentModeId string
---@field availableModes acp.SessionMode[]

---@class acp.SessionMode
---@field id string
---@field name string
---@field description? string

---@class acp.SessionConfigOption
---@field id string
---@field name string
---@field type string
---@field description? string
---@field category? string
---@field currentValue string
---@field options acp.SessionConfigSelectOption[]

---@class acp.SessionConfigSelectOption
---@field value string
---@field name string
---@field description? string

---@alias acp.ToolKind 'read'|'edit'|'delete'|'move'|'search'|'execute'|'think'|'fetch'|'switch_mode'|'other'
---@alias acp.ToolCallStatus 'pending'|'in_progress'|'completed'|'failed'

---@class acp.ToolCall
---@field toolCallId string
---@field title string
---@field kind? acp.ToolKind
---@field status? acp.ToolCallStatus
---@field content? acp.ToolCallContent[]
---@field locations? acp.ToolCallLocation[]
---@field rawInput? any
---@field rawOutput? any

---@class acp.ToolCallUpdate
---@field toolCallId string
---@field title? string
---@field kind? acp.ToolKind
---@field status? acp.ToolCallStatus
---@field content? acp.ToolCallContent[]
---@field locations? acp.ToolCallLocation[]
---@field rawInput? any
---@field rawOutput? any

---@alias acp.ToolCallContent acp.ToolCallContentBlock|acp.ToolCallDiff

---@class acp.ToolCallContentBlock
---@field type 'content'
---@field content acp.ContentBlock[]

---@class acp.ToolCallDiff
---@field type 'diff'
---@field path string
---@field newText string
---@field oldText? string

---@class acp.ToolCallLocation
---@field path string
---@field line? integer

---@alias acp.PlanEntryPriority 'high'|'medium'|'low'
---@alias acp.PlanEntryStatus 'pending'|'in_progress'|'completed'

---@class acp.Plan
---@field entries acp.PlanEntry[]

---@class acp.PlanEntry
---@field content string
---@field priority acp.PlanEntryPriority
---@field status acp.PlanEntryStatus

---@class acp.AvailableCommandsUpdate
---@field availableCommands acp.AvailableCommand[]

---@class acp.AvailableCommand
---@field name string
---@field description string
---@field input? acp.UnstructuredCommandInput

---@class acp.UnstructuredCommandInput
---@field type 'unstructured'
---@field hint string

---@class acp.CurrentModeUpdate
---@field currentModeId string

---@class acp.ConfigOptionUpdate
---@field configOptions acp.SessionConfigOption[]

---@class acp.PermissionOption
---@field optionId string
---@field name string
---@field kind 'allow_once'|'allow_always'|'reject_once'|'reject_always'

---@class acp.PermissionRequestParams
---@field sessionId string
---@field toolCall acp.ToolCallUpdate
---@field options acp.PermissionOption[]

---@alias acp.PermissionResult
---| acp.PermissionCancelled
---| acp.PermissionSelected

---@class acp.PermissionCancelled
---@field outcome 'cancelled'

---@class acp.PermissionSelected
---@field outcome 'selected'
---@field optionId string

local M = {}

local function request(id, method, params)
  return { jsonrpc = '2.0', id = id, method = method, params = params }
end

local function response(id, result)
  return { jsonrpc = '2.0', id = id, result = result }
end

local function notification(method, params)
  return { jsonrpc = '2.0', method = method, params = params }
end

---@class acp.InitializeRequest : symbiont.rpc.Request
---@field method 'initialize'
---@field params acp.InitializeParams

---@class acp.InitializeParams
---@field protocolVersion integer
---@field clientInfo { name: string, version: string }
---@field clientCapabilities acp.ClientCapabilities

---@class acp.ClientCapabilities
---@field terminal boolean
---@field fs? { readTextFile?: boolean, writeTextFile?: boolean }

---@class acp.Result

---@class acp.InitializeResult : acp.Result
---@field protocolVersion integer
---@field agentCapabilities? acp.AgentCapabilities
---@field agentInfo? { name: string, version: string }

---@class acp.AgentCapabilities
---@field loadSession? boolean
---@field promptCapabilities? {
---  image?: boolean,
---  audio?: boolean,
---  embeddedContext?: boolean,
---}
---@field sessionCapabilities? { list?: boolean }

---@param id integer
---@param client_name string
---@param client_version string
---@return acp.InitializeRequest
function M.InitializeRequest(id, client_name, client_version)
  return request(id, 'initialize', {
    protocolVersion = 1,
    clientInfo = { name = client_name, version = client_version },
    clientCapabilities = { terminal = false },
  })
end

---@class acp.ListSessionsRequest : symbiont.rpc.Request
---@field method 'session/list'
---@field params acp.ListSessionsParams

---@class acp.ListSessionsParams
---@field cwd string|userdata

---@class acp.ListSessionsResult : acp.Result
---@field sessions acp.SessionInfo[]
---@field nextCursor? string

---@param id integer
---@param cwd? string
---@return acp.ListSessionsRequest
function M.ListSessionsRequest(id, cwd)
  return request(id, 'session/list', { cwd = cwd or vim.NIL })
end

---@class acp.NewSessionRequest : symbiont.rpc.Request
---@field method 'session/new'
---@field params acp.NewSessionParams

---@class acp.NewSessionParams
---@field cwd string

---@class acp.NewSessionResult : acp.Result
---@field sessionId string
---@field modes? acp.SessionModeState
---@field configOptions? acp.SessionConfigOption[]

---@param id integer
---@param cwd string
---@return acp.NewSessionRequest
function M.NewSessionRequest(id, cwd)
  return request(id, 'session/new', { cwd = cwd, mcpServers = {} })
end

---@class acp.LoadSessionRequest : symbiont.rpc.Request
---@field method 'session/load'
---@field params acp.LoadSessionParams

---@class acp.LoadSessionParams
---@field sessionId string
---@field cwd string

---@class acp.LoadSessionResult : acp.Result
---@field modes? acp.SessionModeState
---@field configOptions? acp.SessionConfigOption[]

---@param id integer
---@param session_id string
---@param cwd string
---@return acp.LoadSessionRequest
function M.LoadSessionRequest(id, session_id, cwd)
  return request(id, 'session/load', { sessionId = session_id, cwd = cwd, mcpServers = {} })
end

---@class acp.PromptResult : acp.Result
---@field stopReason acp.StopReason

---@alias acp.StopReason
---| 'end_turn'
---| 'max_tokens'
---| 'max_turn_requests'
---| 'refusal'
---| 'cancelled'

---@class acp.PromptRequest : symbiont.rpc.Request
---@field method 'session/prompt'
---@field params acp.PromptParams

---@class acp.PromptParams
---@field sessionId string
---@field prompt acp.ContentBlock[]

---@param id integer
---@param session_id string
---@param prompt acp.ContentBlock[]
---@return acp.PromptRequest
function M.PromptRequest(id, session_id, prompt)
  return request(id, 'session/prompt', { sessionId = session_id, prompt = prompt })
end

---@class acp.SetModeRequest : symbiont.rpc.Request
---@field method 'session/setMode'
---@field params acp.SetModeParams

---@class acp.SetModeParams
---@field sessionId string
---@field modeId string

---@class acp.SetModeResult : acp.Result

---@param id integer
---@param session_id string
---@param mode_id string
---@return acp.SetModeRequest
function M.SetModeRequest(id, session_id, mode_id)
  return request(id, 'session/setMode', { sessionId = session_id, modeId = mode_id })
end

---@class acp.SetConfigOptionRequest : symbiont.rpc.Request
---@field method 'session/setConfigOption'
---@field params acp.SetConfigOptionParams

---@class acp.SetConfigOptionParams
---@field sessionId string
---@field configOptionId string
---@field value string

---@class acp.SetConfigOptionResult : acp.Result
---@field configOptions acp.SessionConfigOption[]

---@param id integer
---@param session_id string
---@param config_option_id string
---@param value string
---@return acp.SetConfigOptionRequest
function M.SetConfigOptionRequest(id, session_id, config_option_id, value)
  return request(id, 'session/setConfigOption', {
    sessionId = session_id,
    configOptionId = config_option_id,
    value = value,
  })
end

---@class acp.CancelNotification : symbiont.rpc.Notification
---@field method 'session/cancel'
---@field params acp.CancelParams

---@class acp.CancelParams
---@field sessionId string

---@param session_id string
---@return acp.CancelNotification
function M.CancelNotification(session_id)
  return notification('session/cancel', { sessionId = session_id })
end

---@class acp.PermissionSelectedResponse : symbiont.rpc.SuccessResponse
---@field result acp.PermissionSelected

---@param id integer
---@param option_id string
---@return acp.PermissionSelectedResponse
function M.PermissionSelectedResponse(id, option_id)
  return response(id, { outcome = 'selected', optionId = option_id })
end

---@class acp.PermissionCancelledResponse : symbiont.rpc.SuccessResponse
---@field result acp.PermissionCancelled

---@param id integer
---@return acp.PermissionCancelledResponse
function M.PermissionCancelledResponse(id)
  return response(id, { outcome = 'cancelled' })
end

return M
