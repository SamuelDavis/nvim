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
-- buffer metadata
vim.o.statusline = "%f"

-------------
-- KEYMAPS --
-------------
vim.keymap.set("n", "j", "gj", { noremap = true })
vim.keymap.set("n", "k", "gk", { noremap = true })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

local function map(key, fn, desc, mode)
	vim.keymap.set(mode or "n", "<leader>" .. key, fn, { desc = desc })
end

local prefixes = {}
local function keymap_prefix(prefix_key, prefix_desc)
	prefixes[prefix_key] = prefix_desc
	return function(key, fn, desc, mode)
		map(prefix_key .. key, fn, prefix_desc .. " " .. desc, mode)
	end
end
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		local whichkey = require("which-key")
		for key, description in pairs(prefixes) do
			whichkey.add({
				{ "<leader>" .. key, group = description },
			})
		end
	end,
})

local dmap = keymap_prefix("d", "[D]iagnostic")
local fmap = keymap_prefix("f", "[F]ind")
local rmap = keymap_prefix("r", "[R]eplace")
local cmap = keymap_prefix("c", "[C]ode")
local hmap = keymap_prefix("h", "[H]over")

dmap("o", vim.diagnostic.open_float, "[O]pen")
dmap("p", vim.diagnostic.get_prev, "[P]rev")
dmap("n", vim.diagnostic.get_next, "[N]ext")
dmap("l", vim.diagnostic.setloclist, "[L]ist")

rmap("s", ":s/\\%V", "[S]election", "v")
rmap("l", ":s/", "[L]ine", "v")

cmap("f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, "[F]ormat")

---------
-- LLM --
---------
local uv = vim.uv or vim.loop
local function ping_ollama(host, port, timeout_ms)
	host = host or "127.0.0.1"
	port = port or 11434
	timeout_ms = timeout_ms or 500

	local tcp = uv.new_tcp()
	local done, ok = false, false
	local buf = {}

	tcp:connect(host, port, function(e)
		if e then
			done = true
			return
		end
		tcp:write("GET / HTTP/1.0\r\nHost: " .. host .. "\r\n\r\n")
		tcp:read_start(function(err, chunk)
			if err then
				ok, done = false, true
				return
			end
			if chunk then
				table.insert(buf, chunk)
				return
			end
			local body = table.concat(buf)
			done, ok = true, body:find("Ollama is running", 1, true) ~= nil
		end)
	end)

	vim.wait(timeout_ms, function()
		return done
	end, 10)
	pcall(function()
		tcp:shutdown()
	end)
	pcall(function()
		tcp:close()
	end)

	return ok
end
local model = os.getenv("NVIM_OLLAMA_MODEL")
local ollama_available = ping_ollama() and model

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
	intelephense = {
		settings = {
			intelephense = {
				environment = {
					phpVersion = os.getenv("PHP_VERSION")
						or vim.fn.systemlist("php --version")[1]:match("PHP%s+([%d%.]+)"),
				},
				stubs = {
					"apache",
					"bcmath",
					"bz2",
					"calendar",
					"Core",
					"curl",
					"date",
					"dom",
					"fileinfo",
					"filter",
					"gd",
					"gmp",
					"hash",
					"iconv",
					"json",
					"libxml",
					"mbstring",
					"openssl",
					"pcre",
					"PDO",
					"pdo_mysql",
					"Phar",
					"readline",
					"Reflection",
					"session",
					"SimpleXML",
					"SPL",
					"standard",
					"tokenizer",
					"xml",
					"xmlreader",
					"xmlwriter",
					"zlib",
					"memcache",
					"memcached",
				},
			},
		},
	},
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
local formatters = {
	"stylua",
	"prettier",
	"prettierd",
	"isort",
	"black",
	"gdtoolkit",
}
local ensure_installed = vim.iter({ vim.tbl_keys(servers), formatters }):flatten():totable()
servers["gdscript"] = {}

local function config_telescope()
	local telescope = require("telescope")

	local file_ignore_patterns = vim.iter({
		--misc
		{ "%.ttf", ".git/", "*.lock" },
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
	fmap("f", function()
		builtin.find_files({ hidden = true, no_ignore = true })
	end, "[F]iles")
	fmap("b", builtin.buffers, "[B]uffers")
	fmap("n", builtin.resume, "[N]ext")
	fmap("o", builtin.oldfiles, "[O]ld")
	fmap("g", builtin.live_grep, "[G]rep")
	fmap(".", builtin.current_buffer_fuzzy_find, "[.] Here")
end

local function config_lspconfig()
	local blink = require("blink.cmp")
	local capabilities = blink.get_lsp_capabilities()
	for name, server in pairs(servers) do
		server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
		vim.lsp.config(name, server)
		vim.lsp.enable(name)
	end
end

local function config_blink()
	local blink = require("blink.cmp")

	local keymap = { preset = "super-tab" }
	local sources = { "lsp", "buffer", "path", "snippets" }
	local providers = {
		snippets = {
			opts = {
				extended_filetypes = {
					typescriptreact = { "typescript", "javascript", "html" },
					javascriptreact = { "javascript", "html" },
					typescript = { "javascript" },
				},
			},
		},
		lsp = {
			fallbacks = { "buffer" },
			transform_items = function(_, items)
				local filtered = {}
				for _, item in ipairs(items) do
					local label = item.label or ""
					local detail = item.detail or ""
					local label_description = item.label_description or ""
					local text = label .. " " .. detail .. " " .. label_description
					if not text:match("solid%-js/.*server") then
						table.insert(filtered, item)
					end
				end

				return filtered
			end,
		},
	}

	if ollama_available then
		local minuet = require("minuet")
		keymap["<A-y>"] = minuet and minuet.make_blink_map()
		table.insert(sources, "minuet")
		providers.minuet = {
			name = "minuet",
			module = "minuet.blink",
			async = true,
			timeout_ms = 3000,
			score_offset = 80,
		}
	end

	blink.setup({
		keymap = keymap,
		sources = {
			default = sources,
			providers = providers,
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
		fuzzy = {
			implementation = "lua",
			sorts = { "sort_text", "score", "label" },
		},
		signature = { enabled = true },
	})
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not uv.fs_stat(lazypath) then
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
	{
		"folke/which-key.nvim",
		opts = {
			plugins = {
				presets = {
					motions = false,
				},
			},
			icons = {
				keys = {
					Esc = "⨉ ",
					BS = "↩ ",
				},
			},
		},
	},
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
		dependencies = ollama_available and { "milanglacier/minuet-ai.nvim" } or {},
		config = config_blink,
	},
	{
		"milanglacier/minuet-ai.nvim",
		enabled = model and ollama_available,
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			provider = "openai_fim_compatible",
			n_completions = 1,
			context_window = 512,
			provider_options = {
				openai_fim_compatible = {
					api_key = "TERM",
					name = "Ollama",
					end_point = "http://localhost:11434/v1/completions",
					model = model,
					optional = {
						max_tokens = 56,
						top_p = 0.9,
					},
				},
			},
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
				php = { "prettier" },
				gdscript = { "gdformat" },
			},
		},
	},
	{
		"rmagatti/goto-preview",
		dependencies = { "rmagatti/logger.nvim" },
		event = "BufEnter",
		opts = {},
		config = function()
			local preview = require("goto-preview")
			preview.setup()
			hmap("p", preview.goto_preview_definition, "[P]review")
			hmap("q", preview.close_all_win, "[Q]uit")
		end,
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
		hmap("d", vim.lsp.buf.hover, "[D]ocumentation")

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
