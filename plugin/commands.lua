-- -old line
-- +new line
--  context line
-- +another addition
-- ]]
--   require("aiplugin").preview(diff)
-- end, {})
--
-- vim.api.nvim_create_user_command("DiffPreviewClear", function()
--   vim.api.nvim_buf_clear_namespace(0, require("aiplugin").ns, 0, -1)
-- end, {})
--
local chat=require"aiplugin".chat
local aiplugin=require"aiplugin"
-- local llm_utils=require"aiplugin".llm_utils

vim.api.nvim_create_user_command("ToggleChat",chat.toggle_chat_window,{})
vim.keymap.set("n","<leader>tc","<cmd>ToggleChat<CR>")
-- P(llm_utils)
vim.api.nvim_create_user_command("DoHistory",aiplugin.fill_history,{})
