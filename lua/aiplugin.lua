local M = {}
M.diff = require("diff")
M.chat = require("chat")
M.llm_utils = require("llm_utils")
function M:fill_history()
	local messages = '[{"role":"user","content":"hi"}]'
	local response = M.llm_utils:make_llm_call(messages)
	print(response)
	local history_buf = M.chat.bufs:get_buffer("history")
	vim.api.nvim_buf_set_lines(history_buf, -1, -1, false, vim.split(response.content, "\n", { plain = true }))
end

return M
