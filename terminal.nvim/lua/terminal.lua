local M = {}

M.setup = function()

end

local state = {
	floating = {
		buf = -1,
		win = -1,
		win_view = nil,
	}
}
local create_floating_window = function(opts)
	opts = opts or {}
	local new_buffer=true
	local width = opts.width or math.floor(vim.o.columns * 0.8)
	local height = opts.height or math.floor(vim.o.lines * 0.8)

	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local buf = nil
	if vim.api.nvim_buf_is_valid(opts.buf) then
		buf = opts.buf
		new_buffer=false
	else
		buf = vim.api.nvim_create_buf(false, true)
	end
	local window_config = {
		relative = "editor",
		height = height,
		width = width,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded"
	}

	local win = vim.api.nvim_open_win(buf, true, window_config)
	vim.api.nvim_set_option_value('winhl', 'Normal:Normal',{win=win})
	vim.api.nvim_feedkeys("i","n",false)
	return { buf = buf, win = win }
end


local function toggle_terminal()
	if not vim.api.nvim_win_is_valid(state.floating.win) then
		state.floating = create_floating_window({ buf = state.floating.buf })

		if vim.bo[state.floating.buf].buftype ~= "terminal" then
			vim.cmd.terminal()
		end
		if state.floating.win_view~=nil then
			vim.fn.winrestview(state.floating.win_view)
		end
	else
		state.floating.win_view = vim.fn.winsaveview()
		vim.api.nvim_win_hide(state.floating.win)
		state.floating.win = -1
	end
end
vim.api.nvim_create_user_command("FloatTerminal", toggle_terminal, {})
vim.keymap.set("t","<esc><esc>","<C-\\><C-n>")
vim.keymap.set({ "n", "t" }, "<M-i>", toggle_terminal)


return M
