local curl = require("cURL")
local utils = require("utils")
local uv = vim.uv
local M = {}

function M:get_token()
	if self.token == nil then
		self.token = vim.trim(utils.readFile("/home/neil/.local/share/sec/oaik"))
	end
	return self.token
end

P = function(v)
	print(vim.inspect(v))
	return v
end
---@class ChatMessage
---@field content string|nil
---@field role string|nil
---@field usage table|nil
M.ChatMessage = { content = nil, role = nil, usage = nil }
M.ChatMessage.__index = M.ChatMessage

---@param content string|nil
---@param role string|nil
---@param usage table|nil
---@return ChatMessage
function M.ChatMessage:new(content, role, usage)
	self = setmetatable({}, M.ChatMessage)
	self.content = content
	self.role = role
	self.usage = usage
	return self
end

---@param response string
---@return ChatMessage[]
function M.ChatMessage:from_json_response(response)
	local json_response = vim.fn.json_decode(response)
	if json_response.error ~= nil then
		error("Failed to make llm call:" .. response)
	end

	local message = json_response.choices[1].message
	return M.ChatMessage:new(message.content, message.role, json_response.usage)
end

---@param chat_messages ChatMessage[]
---@param model string|nil
---@return table
function M.ChatMessage.to_message_list(chat_messages, model)
	output_list = {}
	if model == nil then
		model = "gpt-3.5-turbo"
	end
	for _, message in pairs(chat_messages) do
		local role = message.role
		table.insert(output_list, { role = message.role, content = message.content })
	end
	return output_list
end

---@param chat_messages ChatMessage[]
---@param model string|nil
---@return ChatMessage
function M.make_llm_call(chat_messages, model)
	if model == nil then
		model = 'gpt-3.5-turbo'
	end
	local messages = M.ChatMessage.to_message_list(chat_messages, model)
	local json = vim.fn.system({
		"curl", "-s", "-X", "POST",
		"-H", "Content-Type: application/json",
		"-H", "Authorization: Bearer " .. M:get_token(),
		"-d", '{"model":"' .. model .. '","messages":' .. vim.fn.json_encode(messages) .. '}',
		"https://api.openai.com/v1/chat/completions"
	})
	return M.ChatMessage:from_json_response(json)
end

local function recieve_chunk(chunk, on_stdout_chunk)
	for line in chunk:gmatch("[^\n]+") do
		local raw_json = string.gsub(line, "^data: ", "")

		local ok, path = pcall(vim.json.decode, raw_json)
		if not ok then
			goto continue
		end

		path = path.choices
		if path == nil then
			goto continue
		end
		path = path[1]
		if path == nil then
			goto continue
		end
		path = path.delta
		if path == nil then
			goto continue
		end
		path = path.content
		if path == nil then
			goto continue
		end
		if on_stdout_chunk then
			on_stdout_chunk(path)
		end
		::continue::
	end
end
function M.make_streaming_llm_call(chat_messages, model, on_stdout_chunk, on_complete)
	if model == nil then
		model = 'gpt-3.5-turbo'
	end
	local messages = M.ChatMessage.to_message_list(chat_messages, model)
	local data={model=model,messages=messages,stream=true}
	local curl_args = {
		   "--silent",
        "--show-error",
        "--no-buffer",
        "https://api.openai.com/v1/chat/completions",
        "-H",
        "Content-Type: application/json",
        "-H",
        "Authorization: Bearer " .. M:get_token(),
        "-d",
				vim.fn.json_encode(data)
	}
	utils.exec("curl", curl_args, function(chunk) recieve_chunk(chunk,on_stdout_chunk) end, on_complete)
end

return M
