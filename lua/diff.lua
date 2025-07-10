local M = {}

local ns = vim.api.nvim_create_namespace("diffpreview")

------------------------------------------------------------
-- Parse unified diff into structured hunks
------------------------------------------------------------
local function parse_diff(diff)
  local hunks = {}
  local current = nil

  for line in vim.gsplit(diff, "\n") do
    local header = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if header then
      if current then table.insert(hunks, current) end
      current = {
        start = tonumber(header),
        lines = {},
      }
    elseif current then
      table.insert(current.lines, line)
    end
  end
  if current then table.insert(hunks, current) end

  return hunks
end

------------------------------------------------------------
-- Check if hunk can apply cleanly
------------------------------------------------------------
local function can_apply_hunk(bufnr, hunk)
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, hunk.start - 1, hunk.start - 1 + #hunk.lines, false)

  local i = 1
  local buf_i = 1
  while i <= #hunk.lines and buf_i <= #buf_lines do
    local line = hunk.lines[i]
    local sign = line:sub(1, 1)
    local text = line:sub(2)

    if sign == ' ' or sign == '-' then
      local buf_line = buf_lines[buf_i]
      if not buf_line then return false end
      if buf_line ~= text then return false end
      buf_i = buf_i + 1
    end
    i = i + 1
  end

  return true
end

------------------------------------------------------------
-- Render a hunk with virtual lines (non-destructive)
------------------------------------------------------------
local function render_hunk(bufnr, hunk)
  local virt_lines = {}
  local virt_line_positions = {}
  local line_index = hunk.start - 1  -- 0-based
  local offset = 0

  for _, line in ipairs(hunk.lines) do
    local sign = line:sub(1,1)
    local text = line:sub(2)

    if sign == ' ' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, line_index + offset, 0, {
        virt_text = { { "  " .. text, "Comment" } },
        virt_text_pos = "overlay",
      })
      offset = offset + 1

    elseif sign == '-' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, line_index + offset, 0, {
        virt_text = { { "- " .. text, "DiffDelete" } },
        virt_text_pos = "overlay",
      })
      offset = offset + 1

    elseif sign == '+' then
      table.insert(virt_lines, { { "+ " .. text, "DiffAdd" } })
      table.insert(virt_line_positions, line_index + offset)
    end
  end

  -- Place virt_lines *below* the last matched buffer line
  if #virt_lines > 0 then
    local place_at = virt_line_positions[1] or (line_index + offset)
    vim.api.nvim_buf_set_extmark(bufnr, ns, place_at, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
    })
  end
end

------------------------------------------------------------
-- Public: Preview a unified diff
------------------------------------------------------------
function M.preview(diff)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local hunks = parse_diff(diff)
	-- TODO: do can_apply_all_hunks
  for _, hunk in ipairs(hunks) do
    if can_apply_hunk(bufnr, hunk) then
      render_hunk(bufnr, hunk)
    else
      vim.notify("Hunk at line " .. hunk.start .. " can't be applied", vim.log.levels.WARN)
    end
  end
end

return M
