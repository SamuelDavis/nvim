vim.g.mapleader = ","
local home_directory = os.getenv("HOME")

local function directory_exists(path)
	return os.execute("cd " .. path) == 0
end

local undo_directory = home_directory .. "/.vim/undos"
if not directory_exists(undo_directory) then
    print("Creating directory: " .. undo_directory)
	os.execute("mkdir -p " .. undo_directory)
end
local options = {
	-- general
	wrap = false,
	colorcolumn = "80",
	termguicolors = false,
	-- line_numbers
	number = true,
	relativenumber = true,
	scrolloff = 10,
	-- indentation
	tabstop = 4,
	softtabstop = 4,
	shiftwidth = 4,
	expandtab = true,
	smartindent = true,
	-- long-running undos
	swapfile = false,
	backup = false,
	undofile = true,
	undodir = undo_directory,
	-- search
	hlsearch = false,
	incsearch = true
}

for option, value in pairs(options) do
	vim.opt[option] = value
end

local commands = {
	colorscheme = "slate",
	syntax = "on"
}

for command, value in pairs(commands) do
	vim.cmd(command .. " " .. value)
end

