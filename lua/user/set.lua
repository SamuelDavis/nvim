vim.g.mapleader = ","
vim.opt.colorcolumn = "80"
vim.opt.termguicolors = true

-- line numbers
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 8

-- gutter icons
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

-- indentation
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- long-running undos
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"

-- save regularly
vim.opt.updatetime = 50

-- search
vim.opt.hlsearch = false
vim.opt.incsearch = true
