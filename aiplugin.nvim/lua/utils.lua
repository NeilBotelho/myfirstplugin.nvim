local M = {}
local uv = vim.uv
function M.readFile(path)
	local output = {}
	local fd, err_msg, err = uv.fs_open(path, "r", "0")
	assert(not err, err_msg)

	local stat, err, err_name = uv.fs_fstat(fd)
	assert(not err, err_name)
	--
	local data, err, err_name = uv.fs_read(fd, stat.size, 0)
	assert(not err, err_name)
	uv.fs_close(fd)
	return data
end

--- For the record this is flagrantly taken from https://github.com/Bryley/neoai.nvim/
---Executes command getting stdout chunks
---@param cmd string
---@param args string[]
---@param on_stdout_chunk fun(chunk: string): nil
---@param on_complete fun(err: string?, output: string?): nil
function M.exec(cmd, args, on_stdout_chunk, on_complete)
	local stdout = vim.loop.new_pipe()
	local function on_stdout_read(_, chunk)
		if chunk then
			vim.schedule(function()
				on_stdout_chunk(chunk)
			end)
		end
	end

	local stderr = vim.loop.new_pipe()
	local stderr_chunks = {}
	local function on_stderr_read(_, chunk)
		if chunk then
			table.insert(stderr_chunks, chunk)
		end
	end

	local handle=nil

	handle, err = vim.uv.spawn(cmd, {
		args = args,
		stdio = { nil, stdout, stderr },
	}, function(code)
		stdout:close()
		stderr:close()
		handle:close()

		vim.schedule(function()
			if code ~= 0 then
				on_complete(vim.trim(table.concat(stderr_chunks, "")))
			else
				on_complete()
			end
		end)
	end)

	if not handle then
		on_complete(cmd .. " could not be started: " .. err)
	else
		stdout:read_start(on_stdout_read)
		stderr:read_start(on_stderr_read)
	end
end

return M
