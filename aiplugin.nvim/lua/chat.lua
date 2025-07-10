local M = {}
local llm_utils = require("llm_utils")
M.chat_win = nil
M.chat_buf = nil
M.state = {
	prompt_ext = nil,
	is_running = false
}

M.ns = vim.api.nvim_create_namespace("aiplugin_chat")

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("my_plugin_highlights", { clear = true }),
	callback = function()
		vim.api.nvim_set_hl(0, "ChatPrompt", {
			fg = "#1e1e2e",
			bg = "#fab387",
			bold = true,
		})

		vim.api.nvim_set_hl(0, "ChatUser", {
			fg = "#1e1e2e",
			bg = "#89b4fa",
			bold = true,
		})

		vim.api.nvim_set_hl(0, "ChatAssistant", {
			fg = "#1e1e2e",
			bg = "#a6e3a1",
			bold = true,
			italic = true,
		})
		vim.api.nvim_set_hl(0, "ChatNormal", {
			bg = "#1e1e2e", -- darker than #313244
			fg = "#cdd6f4", -- readable, not too bright
		})
	end,
})

---@param line integer|nil
function M:set_prompt_ext(line)
	if self.state.prompt_ext then
		if not vim.api.nvim_buf_del_extmark(0, self.ns, self.state.prompt_ext) then
			return
		end
		self.state.prompt_ext = nil
	end
	if line == nil then
		line = vim.api.nvim_buf_line_count(self.chat_buf) - 2
	end
	if line <= 0 then
		line = 2
	end
	self.state.prompt_ext = vim.api.nvim_buf_set_extmark(self.chat_buf, self.ns, line, 0,
		{ virt_lines = { { { " Prompt:", "ChatPrompt" } } }, virt_lines_above = false })
end

---@param line nil|integer
function M.clear_ext_mark(line)
	if line == nil then
		line = vim.api.nvim_win_get_cursor(M.chat_win)[1]
	end
	local ext_marks = vim.api.nvim_buf_get_extmarks(M.chat_buf, M.ns, 0, -1, {})
	for _, mark in pairs(ext_marks) do
		if mark[2] == line then
			vim.api.nvim_buf_del_extmark(M.chat_buf, M.ns, mark[1])
		end
	end
end

function M.reset_session()
	vim.api.nvim_win_close(M.chat_win, false)
	vim.api.nvim_buf_delete(M.chat_buf, {})
	M.chat_buf = nil
	M.state.prompt_ext = nil
	M.state.is_running = false
	M.toggle_chat_window()
end

function M.set_chat_buffer_keymaps()
	vim.keymap.set("n", "<leader>st", function()
			local line = vim.api.nvim_win_get_cursor(M.chat_win)[1]
			M:set_prompt_ext(line)
		end,
		{ buffer = M:get_chat_buffer() }
	)
	vim.keymap.set("n", "<leader>cl", M.clear_ext_mark, { buffer = M:get_chat_buffer() })
	vim.keymap.set("n", "<leader>r", M.reset_session, { buffer = M:get_chat_buffer() })
	vim.keymap.set("n", "<leader>mi", function()
		M:update_history({ "hellow", "world" }, "Human")
	end, { buffer = M:get_chat_buffer() })

	vim.keymap.set("n", "<CR>", M.send_prompt_stream, { buffer = M:get_chat_buffer() })
end

---@return integer
function M:get_chat_buffer()
	if self.chat_buf == nil or not vim.api.nvim_buf_is_valid(self.chat_buf) then
		self.chat_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_text(self.chat_buf, 0, 0, 0, 0, { "", "", "" })
		self:set_prompt_ext()
		self.set_chat_buffer_keymaps()
		vim.api.nvim_set_option_value("filetype", "markdown", { scope = "local", buf = self.chat_buf })
	end

	vim.api.nvim_set_option_value("bufhidden", "hide", { scope = "local", buf = self.chat_buf })
	return self.chat_buf
end

---@return integer
function M:create_chat_window()
	local height = math.floor(vim.api.nvim_win_get_height(0) * 0.9)
	local width = math.floor(vim.api.nvim_win_get_width(0) * 0.9)
	local chat_win = vim.api.nvim_open_win(0, true, {
		relative = "win",
		bufpos = { 1, 1 },
		width = width,
		height = height,
		border = "rounded",
		style = "minimal"
	})
	vim.api.nvim_set_option_value("number", true, { scope = "local", buf = self.chat_win })
	vim.api.nvim_set_option_value("winhighlight", "Normal:ChatNormal,EndOfBuffer:ChatNormal", { win = chat_win })
	vim.cmd("set number")
	self.chat_win = chat_win
	return chat_win
end

function M.toggle_chat_window()
	if M.chat_win ~= nil and vim.api.nvim_win_is_valid(M.chat_win) then
		vim.api.nvim_win_close(M.chat_win, false)
		M.chat_win = nil
		return
	end
	local chat_win = M:create_chat_window()
	vim.cmd("set number")
	local chat_buf = M:get_chat_buffer()
	vim.api.nvim_win_set_buf(chat_win, chat_buf)
	local line_count = vim.api.nvim_buf_line_count(0)
	vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
end

function M:clear_invalid_extmarks()
	local last_pos = nil
	local ext_marks = vim.api.nvim_buf_get_extmarks(M.chat_buf, M.ns, 0, -1, {})

	for i = #ext_marks, 1, -1 do
		local mark = ext_marks[i]
		if mark[1] ~= self.state.prompt_ext then
			if last_pos and last_pos - mark[2] < 2 then
				vim.api.nvim_buf_del_extmark(self.chat_buf, self.ns, mark[1])
				last_pos = mark[2]
			end
		end
	end
end

---@param lines string[]
---@param role string
---@return integer extmark
function M:update_history(lines, role)
	local prompt_pos = vim.api.nvim_buf_get_extmark_by_id(self.chat_buf, self.ns, self.state.prompt_ext, {})
	if #prompt_pos == 0 then
		error("Failed to update chat history: Can't find prompt ext mark")
	end
	local insertion_row = prompt_pos[1] - 1
	if insertion_row < 1 then
		insertion_row = 1
	end
	table.insert(lines, #lines + 1, "")
	vim.api.nvim_buf_set_lines(self.chat_buf, insertion_row, insertion_row, false, lines)
	local get_hl_group = function(message_role)
		if message_role == "user" then
			return "ChatUser"
		else
			return "ChatAssistant"
		end
	end
	local get_role_display = function(message_role)
		if message_role == "user" then
			return " User"
		else
			return " Assistant"
		end
	end
	local extmark = vim.api.nvim_buf_set_extmark(self.chat_buf, self.ns, insertion_row, 0,
		{ virt_lines = { { { get_role_display(role) .. ":", get_hl_group(role) } } }, virt_lines_above = true })
	self:clear_invalid_extmarks()
	return extmark
end

---@return ChatMessage[]
function M.get_message_history()
	local messages = {}
	-- Get all ext_marks other than prompt
	local ext_marks = vim.api.nvim_buf_get_extmarks(M.chat_buf, M.ns, 0, -1, { details = true })

	local final_pos = nil
	for i = #ext_marks, 1, -1 do
		if ext_marks[i][1] == M.state.prompt_ext then
			final_pos = ext_marks[i][2]
			table.remove(ext_marks, i)
			break
		end
	end
	if final_pos == nil then
		error("Failed to find prompt extmark when getting message history")
	end
	local current_idx = 1
	local next_idx = 2

	-- If there is no history then return
	if #ext_marks == 0 then
		return {}
	end

	-- Get the content between 2 ext marks
	while next_idx <= #ext_marks do
		local role = nil
		if current_idx % 2 == 1 then
			role = "user"
		else
			role = "assistant"
		end
		local lines = vim.api.nvim_buf_get_lines(M.chat_buf, ext_marks[current_idx][2], ext_marks[next_idx][2], true)
		local content = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
		table.insert(messages, llm_utils.ChatMessage:new(content, role, nil))
		current_idx = current_idx + 1
		next_idx = next_idx + 1
	end
	-- Get content between last history mesage and prompmt
	local role = nil
	if current_idx % 2 == 1 then
		role = "user"
	else
		role = "assistant"
	end
	local lines = vim.api.nvim_buf_get_lines(M.chat_buf, ext_marks[current_idx][2], final_pos, true)
	local content = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
	table.insert(messages, llm_utils.ChatMessage:new(content, role, nil))

	return messages
end

function M:clear_prompt()
	local line = vim.api.nvim_buf_get_extmark_by_id(self.chat_buf, self.ns, self.state.prompt_ext, {})[1]
	vim.api.nvim_buf_set_lines(self.chat_buf, line + 1, -1, false, { "", "" })
end

---@param clear boolean|nil
---@return string
function M:get_prompt_content(clear)
	local prompt_start_line = vim.api.nvim_buf_get_extmark_by_id(self.chat_buf, self.ns, self.state.prompt_ext, {})[1]
	prompt_start_line = prompt_start_line + 1
	local prompt = vim.api.nvim_buf_get_lines(M.chat_buf, prompt_start_line, -1, false)
	if clear ~= nil and clear == true then
		local number_of_lines = vim.api.nvim_buf_line_count(M.chat_buf)
		vim.api.nvim_buf_set_lines(M.chat_buf, prompt_start_line, number_of_lines, false, { "", "" })
	end
	return table.concat(prompt, "\n"):match("^%s*(.-)%s*$")
end

function M.streaming_call(messages)
	local assistant_ext = M:update_history({}, "assistant")
	local current_line = vim.api.nvim_buf_get_extmark_by_id(M.chat_buf, M.ns, assistant_ext, {})[1] + 1
	local function streaming_update_buffer(chunk)
		local line_content = vim.api.nvim_buf_get_lines(M.chat_buf, current_line, current_line + 1, true)[1]
		local chunk_lines = vim.split(chunk, "\n", {})
		chunk_lines[1] = line_content .. chunk_lines[1]
		vim.api.nvim_buf_set_lines(M.chat_buf, current_line, current_line + 1, false, chunk_lines)
		current_line = current_line + #chunk_lines - 1
	end

	local function on_complete(error_msg)
		if error_msg then
			error(error_msg)
		else
			vim.api.nvim_buf_set_lines(M.chat_buf, current_line + 1, current_line + 1, false, { "", "" })
		end
	end
	-- streaming_update_buffer("hello ")
	-- streaming_update_buffer("neil\n")
	-- streaming_update_buffer("what can we do")
	-- on_complete()
	llm_utils.make_streaming_llm_call(messages, "gpt-3.5-turbo", streaming_update_buffer, on_complete)
end

---@return nil?

function M.send_prompt_stream()
	local prompt = M:get_prompt_content(true)
	if not prompt:find("%S") then
		return
	end

	local ok, chat_messages, err_msg
	chat_messages = M.get_message_history()
	local function fail_cleanup(message, err)
		M.state.is_running = false
		error(message .. err)
	end
	-- TODO: pull roles from global intially then make it based on model/provider
	table.insert(chat_messages, llm_utils.ChatMessage:new(prompt, "user"))

	if M.state.is_running then
		error("Another prompt is currently running")
	else
		M.state.is_running = true
	end
	-- Add user prompt to history
	local lines = vim.split(prompt, "\n", {})
	if #chat_messages == 1 then
		table.insert(lines, "")
	end
	ok, err_msg = pcall(
		function(lines, role) M:update_history(lines, role) end,
		lines,
		"user"
	)
	if not ok then
		fail_cleanup("Failed to update history:", err_msg)
	end
	ok, err_msg = pcall(M.streaming_call, chat_messages)
	if not ok then
		fail_cleanup("Failed to stream llm call:", err_msg)
	end
	M.state.is_running = false
end

function M.send_prompt()
	local prompt = M:get_prompt_content(true)
	if not prompt:find("%S") then
		return
	end

	local response, ok, chat_messages, err_msg
	chat_messages = M.get_message_history()
	local function fail_cleanup(message, err)
		M.state.is_running = false
		error(message .. err)
	end
	-- TODO: pull roles from global intially then make it based on model/provider
	table.insert(chat_messages, llm_utils.ChatMessage:new(prompt, "user"))

	if M.state.is_running then
		error("Another prompt is currently running")
	else
		M.state.is_running = true
	end
	-- Add user prompt to history

	local lines = vim.split(prompt, "\n", {})
	if #chat_messages == 1 then
		table.insert(lines, "")
	end
	ok, err_msg = pcall(
		function(lines, role) M:update_history(lines, role) end,
		lines,
		"user"
	)
	if not ok then
		fail_cleanup("Failed to update history:", err_msg)
	end

	ok, response = pcall(llm_utils.make_llm_call, chat_messages, nil)
	if not ok then
		fail_cleanup("Failed to make llm call", response)
	end
	local response_lines = vim.split(response.content, "\n")


	ok, err_msg = pcall(function(lines, role) M:update_history(lines, role) end, response_lines, "assistant")
	if not ok then
		fail_cleanup("Failed to update history:", err_msg)
	end
	M.state.is_running = false
end

return M
