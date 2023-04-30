vim.g.mapleader = ","
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- paste+replace without losing yanked value
vim.keymap.set("n", "<leader>p", "\"_dP")
vim.keymap.set("v", "<leader>p", "\"_dP")

-- yank to system keyboard
vim.keymap.set("n", "<leader>Y", "\"+y")
vim.keymap.set("v", "<leader>Y", "\"+y")
-- paste from system keyboard
vim.keymap.set("n", "<leader>P", "\"+p")
vim.keymap.set("v", "<leader>P", "\"_d\"+p")

--quick-open terminal
vim.keymap.set("n", "<leader>t", vim.cmd.terminal)
