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
vim.opt.listchars = { tab = "| ", trail = "·", nbsp = "␣" }
vim.opt.breakindent = true
-- cursor positioning
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 10
vim.opt.colorcolumn = "80"
-- preview commands
vim.opt.inccommand = "split"
-- code folds
vim.opt.foldenable = true
vim.opt.foldmethod = "indent"
vim.opt.foldexpr = nil
vim.opt.foldlevel = 9999
-- indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
-- enable mouse in all modes
vim.o.mouse = "a"
-- search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.cmd.colorscheme("retrobox")
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

-------------
-- KEYMAPS --
-------------
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

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
local cmap = keymap_prefix("c", "[C]ode")

dmap("o", vim.diagnostic.open_float, "[O]pen")
dmap("p", vim.diagnostic.get_prev, "[P]rev")
dmap("n", vim.diagnostic.get_next, "[N]ext")
dmap("l", vim.diagnostic.setloclist, "[L]ist")

rmap("s", ":s/\\%V", "[S]election", "v")
rmap("l", ":s/", "[L]ine", "v")

cmap("f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, "[F]ormat")

-------------
-- PLUGINS --
-------------
local servers = {
	-- servers
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
	denols = {
		root_dir = function(bufnr, on_dir)
			local root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc" })
			if root then
				on_dir(root)
			end
		end,
	},
	ts_ls = {
		root_dir = function(bufnr, on_dir)
			local is_deno = vim.fs.root(bufnr, { "deno.json", "deno.jsonc" })
			if is_deno then
				return
			end
			local root = vim.fs.root(bufnr, { "package.json" }) or vim.fn.getcwd()
			on_dir(root)
		end,
	},
	"cssls",
	"pyright",
	"intelephense",
	"bashls",
	-- formatters
	"stylua",
	"prettierd",
	"isort",
	"black",
	"pretty-php",
	"gdtoolkit",
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
local formatters = {}
local ensure_installed = vim.iter({ vim.tbl_keys(servers), formatters }):flatten():totable()

function config_telescope()
	local telescope = require("telescope")

	local file_ignore_patterns = vim.iter({
		--misc
		{ "%.ttf" },
		-- audio
		{ "%.mp3", "%.wav" },
		-- images
		{ "%.png", "%.swf", "%.svg" },
		-- godot
		{ "%.uid", "%.import", "%.db", "%.tscn", "%.tres", "%.godot" },
		-- vendor
		{ "package%-lock.json", "node_modules/", "vendor/" },
		-- build
		{ "dist/" },
	})
		:flatten()
		:totable()

	telescope.setup({
		defaults = {
			file_ignore_patterns = file_ignore_patterns,
		},
	})

	pcall(telescope.load_extension, "fzf")
	pcall(telescope.load_extension, "ui-select")

	local builtin = require("telescope.builtin")
	dmap("l", builtin.diagnostics, "[L]ist")
	fmap("f", builtin.find_files, "[F]iles")
	fmap("b", builtin.buffers, "[B]uffers")
	fmap("n", builtin.resume, "[N]ext")
	fmap("r", builtin.oldfiles, "[R]ecent")
	fmap("g", builtin.live_grep, "[G]rep")
	fmap(".", builtin.current_buffer_fuzzy_find, "[.] Here")
end

function config_lspconfig()
	local blink = require("blink.cmp")
	local capabilities = blink.get_lsp_capabilities()
	for name, server in pairs(servers) do
		server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
		vim.lsp.config(name, server)
		vim.lsp.enable(name)
	end
end

function config_luasnip()
	local snip = require("luasnip")
	local text = snip.text_node
	local cursor = snip.insert_node
	snip.filetype_extend("javascriptreact", { "javascript" })
	snip.filetype_extend("typescriptreact", { "typescript", "javascriptreact", "javascript" })

	snip.add_snippets("html", {
		snip.snippet("favicon", {
			snip.text_node('<link rel="icon" type="image/png" href="data:image/png;base64,iVBORw0KGgo=">'),
		}),
	})

	snip.add_snippets("javascript", {
		snip.snippet("defunc", {
			text("export default function"),
			cursor(1),
			text("("),
			cursor(2),
			text(") { return ("),
			cursor(3, "null"),
			text("); }"),
		}),
	})
end

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
	{ "NMAC427/guess-indent.nvim", opts = {} },
	{ "windwp/nvim-autopairs", opts = {} },
	{ "folke/which-key.nvim", opts = {} },
	{
		"nvim-telescope/telescope.nvim",
		dependencies = {
			{ "nvim-lua/plenary.nvim" },
			{ "nvim-telescope/telescope-ui-select.nvim" },
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
		},
		opts = {},
		config = config_telescope,
	},
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			{ "mason-org/mason-lspconfig.nvim", opts = {} },
			{
				"WhoIsSethDaniel/mason-tool-installer.nvim",
				opts = { ensure_installed = ensure_installed },
			},
			{ "j-hui/fidget.nvim", opts = {} },
			{ "saghen/blink.cmp", opts = {} },
		},
		opts = {},
		config = config_lspconfig,
	},
	{
		"saghen/blink.cmp",
		opts = {
			keymap = { preset = "super-tab" },
			snippets = { preset = "luasnip" },
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
	{
		"stevearc/conform.nvim",
		opts = {
			cmd = { "ConformInfo" },
			formatters_by_ft = {
				lua = { "stylua" },
				json = { "prettierd" },
				html = { "prettierd" },
				javascript = { "prettierd" },
				javascriptreact = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				python = { "black", "isort" },
				php = { "pretty-php", "duster" },
				gdscript = { "gdformat" },
			},
		},
	},
	-- Snippet Engine
	{
		"L3MON4D3/LuaSnip",

		build = (function()
			-- Build Step is needed for regex support in snippets.
			-- This step is not supported in many windows environments.
			-- Remove the below condition to re-enable on windows.
			if vim.fn.has("win32") == 1 or vim.fn.executable("make") == 0 then
				return
			end
			return "make install_jsregexp"
		end)(),

		opts = {},
		config = config_luasnip,
	},
})

--------------
-- AUTOCMDS --
--------------
vim.api.nvim_create_autocmd({ "BufWritePre", "FocusLost", "BufLeave" }, {
	desc = "Format on save",
	pattern = "*",
	group = vim.api.nvim_create_augroup("Autoformat", { clear = true }),
	callback = function(ev)
		if
			vim.api.nvim_buf_is_valid(ev.buf)
			and vim.bo[ev.buf].buftype == ""
			and vim.bo[ev.buf].modified
			and not vim.bo[ev.buf].readonly
		then
			require("conform").format({
				buf = ev.buf,
				lsp_format = "fallback",
			}, function()
				vim.cmd("silent! write")
			end)
		end
	end,
})

vim.api.nvim_create_autocmd({ "BufReadPost" }, {
	desc = "Fix Code Folding",
	pattern = "*",
	group = vim.api.nvim_create_augroup("Set Buffer Options", { clear = true }),
	callback = function(ev)
		local filetype = vim.bo[ev.buf].filetype
		if filetype == "python" then
			vim.opt.foldmethod = "indent"
			vim.opt.foldexpr = nil
		else
			vim.opt.foldmethod = "expr"
			vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
		end
	end,
})

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
		cmap("a", vim.lsp.buf.code_action, "[A]ction", { "n", "x" })
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
