local args = vim.fn.argv(0)
if arg ~= "" then
	local path = vim.fn.fnamemodify(args, ":p")
	if vim.fn.isdirectory(path) == 0 then
		path = vim.fn.fnamemodify(args, ":h")
	end
	if vim.fn.isdirectory(path) == 1 then
		vim.cmd.cd(path)
		vim.fn.remove(vim.v.argv, 1)
	end
end

-------------
-- OPTIONS --
-------------
vim.g.mapleader = ","
vim.g.maplocalleader = vim.g.mapleader
-- new split positioning
vim.opt.splitright = true
vim.opt.splitbelow = true
-- buffer margins
vim.opt.number = true
vim.opt.showmode = false
vim.opt.cursorline = true
-- saving
vim.opt.undofile = true
vim.opt.updatetime = 150
vim.opt.timeoutlen = 300
-- clarify whitespace
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.opt.breakindent = true
-- cursor positioning
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 10
vim.opt.colorcolumn = "80"
-- preview commands
vim.opt.inccommand = "split"
-- code folds
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldlevel = 9999
-- indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
-- enable mouse in all modes
vim.o.mouse = "a"
-- search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.cmd.colorscheme("slate")
-- prompt before clobbering buffer
vim.o.confirm = true
-- clipboard
vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)
-- less destructive undos
local undopoints = { " ", ",", ".", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}" }
for _, ch in ipairs(undopoints) do
	vim.keymap.set("i", ch, ch .. "<C-g>u", { noremap = true })
end

------------
-- KEYMAP --
------------
local function map(key, fn, desc, mode)
	vim.keymap.set(mode or "n", "<leader>" .. key, fn, { desc = desc })
end

local function keymap_prefix(prefix_key, prefix_desc)
	prefix_key = prefix_key
	vim.api.nvim_create_autocmd("User", {
		callback = function()
			require("which-key").add({ "<leader>" .. prefix_key, group = prefix_desc })
		end,
	})

	return function(key, fn, desc, mode)
		map(prefix_key .. key, fn, prefix_desc .. " " .. desc, mode)
	end
end

local dmap = keymap_prefix("d", "[D]iagnostic")
local fmap = keymap_prefix("f", "[F]ind")
local rmap = keymap_prefix("r", "[R]eplace")

dmap("o", vim.diagnostic.open_float, "[O]pen")
dmap("p", vim.diagnostic.open_float, "[P]rev")
dmap("n", vim.diagnostic.open_float, "[N]ext")
dmap("c", vim.diagnostic.open_float, "[C]ode")

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
rmap("s", ":s/\\%V", "[S]election", "v")
rmap("l", ":s/", "[L]ine", "v")

-------------
-- PLUGINS --
-------------

local formatters = { "stylua", "isort", "black", "prettierd", "prettier", "pretty-php", "duster", "gdtoolkit" }
local servers = {
	lua_ls = {
		settings = {
			Lua = {
				diagnostics = {
					globals = { "vim" },
					disable = { "missing-fields" },
				},
			},
		},
	},
	"pyright",
	"typescript-language-server",
	"intelephense",
	"emmet-ls",
	"bashls",
}
local _servers = {}
for k, v in pairs(servers) do
	if type(k) == "number" then
		_servers[v] = {}
	else
		_servers[k] = v
	end
end
servers = _servers
local servers_to_enable = vim.tbl_deep_extend("force", {
	gdscript = {}, -- gdscript is installed by Godot, not Mason
}, servers)

local lsps = vim.tbl_keys(servers)
local lspconfig_ignore = { "typescript-language-server", "emmet-ls" }
local ensure_installed = vim.iter({ lsps, lspconfig_ignore }):flatten():totable()
local file_ignore_patterns = vim.iter({
		--misc
		{ "%.ttf" },
		-- audio
		{ "%.mp3", "%.wav" },
		-- images
		{ "%.png", "%.swf",    "%.svg" },
		-- godot
		{ "%.uid", "%.import", "%.db", "%.tscn", "%.tres", "%.godot" },
	})
	:flatten()
	:totable()

local function config_telescope()
	local telescope = require("telescope")
	local builtin = require("telescope.builtin")
	local config = require("telescope.config")

	config.set_defaults({ file_ignore_patterns = file_ignore_patterns })

	pcall(telescope.load_extension, "fzf")
	pcall(telescope.load_extension, "ui-select")

	dmap("l", builtin.diagnostics, "[L]ist")
	fmap("f", builtin.find_files, "[F]iles")
	fmap("b", builtin.buffers, "[B]uffers")
	fmap("n", builtin.resume, "[N]ext")
	fmap("r", builtin.oldfiles, "[R]ecent")
	fmap("g", builtin.live_grep, "[G]rep")
	fmap(".", builtin.current_buffer_fuzzy_find, "[.] Here")
end

local function config_lspconfig()
	local lspconfig = require("lspconfig")
	local blink = require("blink.cmp")
	local capabilities = blink.get_lsp_capabilities()
	for name, server in pairs(servers_to_enable) do
		server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
		server.on_attach = function(client)
			local path = client.config.root_dir
			if vim.fn.isdirectory(path) == 1 then
				vim.cmd.cd(path)
			end
		end
		vim.lsp.config(name, server)
		vim.lsp.enable(name)
		if not vim.tbl_contains(lspconfig_ignore, name) then
			lspconfig[name].setup(server)
		end
	end
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
	callback = function(event)
		vim.diagnostic.config({})

		local builtin = require("telescope.builtin")
		fmap("d", builtin.lsp_definitions, "[D]efinition")
		fmap("r", builtin.lsp_references, "[R]eferences")
		fmap("I", builtin.lsp_implementations, "[I]mplementations")
		fmap("T", builtin.lsp_type_definitions, "[T]ype definitions")
		fmap("s", builtin.lsp_dynamic_workspace_symbols, "[S]ymbols (Workspace)")
		fmap("S", builtin.lsp_document_symbols, "[S]ymbols (Document)")
		fmap("D", vim.lsp.buf.declaration, "[D]eclaration")

		rmap("n", vim.lsp.buf.rename, "[N]ame")
		map("ca", vim.lsp.buf.code_action, "[C]ode [A]ction", {}, { "n", "x" })
		map("cf", vim.lsp.buf.format, "[C]ode [F]ormat")
		map("hd", vim.lsp.buf.hover, "[H]over [D]ocumentation")

		local client = vim.lsp.get_client_by_id(event.data.client_id)

		local optional_autocmds = {
			{
				vim.lsp.protocol.Methods.textDocument_documentHighlight,
				function()
					local highlight_augroup = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
					vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
						buffer = event.buf,
						group = highlight_augroup,
						callback = vim.lsp.buf.document_highlight,
					})

					vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
						buffer = event.buf,
						group = highlight_augroup,
						callback = vim.lsp.buf.clear_references,
					})

					vim.api.nvim_create_autocmd("LspDetach", {
						group = vim.api.nvim_create_augroup("lsp-detach", { clear = true }),
						callback = function(event2)
							vim.lsp.buf.clear_references()
							vim.api.nvim_clear_autocmds({
								group = "lsp-highlight",
								buffer = event2.buf,
							})
						end,
					})
				end,
			},
			{
				vim.lsp.protocol.Methods.textDocument_inlayHint,
				function()
					map("th", function()
						vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({
							bufnr = event.buf,
						}))
					end, "[T]oggle Inlay [H]ints")
				end,
			},
		}

		if client then
			for _, entry in pairs(optional_autocmds) do
				local capability = entry[1]
				local callback = entry[2]
				if client:supports_method(capability) then
					callback()
				end
			end
		end
	end,
})

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		error("Error cloning lazy.nvim:\n" .. out)
	end
end
local rtp = vim.opt.rtp
rtp:prepend(lazypath)
require("lazy").setup({
	"NMAC427/guess-indent.nvim",
	{
		"folke/which-key.nvim",
		event = "VimEnter",
		opts = { delay = 0 },
	},
	{ "windwp/nvim-autopairs", opts = {} },
	{
		"nvim-telescope/telescope.nvim",
		event = "VimEnter",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
			"nvim-telescope/telescope-ui-select.nvim",
		},
		opts = {},
		config = config_telescope,
	},
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			{ "mason-org/mason.nvim",           opts = {} },
			{ "mason-org/mason-lspconfig.nvim", opts = {} },
			{
				"WhoIsSethDaniel/mason-tool-installer.nvim",
				opts = { ensure_installed = ensure_installed },
			},
			{ "j-hui/fidget.nvim", opts = {} },
			"saghen/blink.cmp",
		},
		config = config_lspconfig,
	},
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = { "ConformInfo" },
		keys = {},
		opts = {
			notify_on_error = true,
			formatters_by_ft = {
				lua = { "stylua" },
				python = { "isort", "black" },
				javascript = { "prettierd", "prettier", stop_after_first = true },
				typescript = { "prettierd", "prettier", stop_after_first = true },
				javascriptreact = { "prettierd", "prettier", stop_after_first = true },
				typescriptreact = { "prettierd", "prettier", stop_after_first = true },
				php = { "pretty-php", "duster" },
				gdscript = { "gdformat" },
			},
		},
	},
	{
		"saghen/blink.cmp",
		event = "VimEnter",
		version = "1.*",
		opts = {
			keymap = {
				preset = "super-tab",
				["<CR>"] = { "accept", "fallback" },
			},
			completion = {
				documentation = { auto_show = true, auto_show_delay_ms = 250 },
				menu = {
					draw = {
						components = {
							kind_icon = {
								text = function(ctx)
									return ctx.kind
								end,
							},
						},
					},
				},
			},
			sources = {
				default = { "lsp", "path", "buffer" },
				providers = {
					lsp = { score_offset = 0, fallbacks = {} },
					path = { score_offset = -10 },
					buffer = { score_offset = -30 },
				},
			},
			fuzzy = {
				implementation = "lua",
				sorts = { "sort_text", "score", "label" },
			},
			signature = { enabled = true },
		},
	},
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		main = "nvim-treesitter.configs",
		opts = {
			auto_install = true,
			highlight = { enable = true },
			indent = { enable = true, disable = { "gdscript" } },
		},
	},
})

--------------
-- AUTOCMDS --
--------------
vim.api.nvim_create_autocmd({ "BufWritePre", "FocusLost", "BufLeave" }, {
	desc = "Format on save",
	pattern = "*",
	group = vim.api.nvim_create_augroup("Autoformat", { clear = true }),
	callback = function(args)
		if
			vim.api.nvim_buf_is_valid(args.buf)
			and vim.bo[args.buf].buftype == ""
			and vim.bo[args.buf].modified
			and not vim.bo[args.buf].readonly
		then
			require("conform").format({
				buf = args.buf,
				lsp_format = "fallback",
			}, function()
				vim.cmd("silent! write")
			end)
		end
	end,
})
