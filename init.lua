local MARKERS = { "deno.json", "deno.jsonc", "package.json", "project.godot", ".git" }

local function project(path)
	path = (path == nil or path == "") and vim.api.nvim_buf_get_name(0) or path
	if path == "" then
		return nil
	end
	local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
	local hit = vim.fs.find(MARKERS, { path = dir, upward = true, limit = 1 })[1]
	if not hit then
		return nil
	end
	local marker, kind = vim.fs.basename(hit), "git"
	if marker:match("^deno%.jsonc?$") then
		kind = "deno"
	elseif marker == "package.json" then
		kind = "node"
	elseif marker == "project.godot" then
		kind = "godot"
	end
	return { root = vim.fs.dirname(hit), kind = kind }
end

local target = vim.fn.argv(0)
if type(target) == "string" and target ~= "" then
	local path = vim.fn.fnamemodify(target, ":p")
	if vim.fn.isdirectory(path) == 1 then
		vim.cmd.cd(path)
	else
		local p = project(path)
		vim.cmd.cd(p and p.root or vim.fs.dirname(path))
	end
end

-------------
-- OPTIONS --
-------------
vim.g.mapleader = ","
vim.g.maplocalleader = vim.g.mapleader
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.number = true
vim.opt.showmode = false
vim.opt.cursorline = true
vim.opt.undofile = true
vim.opt.updatetime = 150
vim.opt.timeoutlen = 300
vim.opt.list = true
vim.opt.listchars = { tab = "| ", trail = "·", nbsp = "␣" }
vim.opt.breakindent = true
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 10
vim.opt.colorcolumn = "80"
vim.opt.inccommand = "split"
vim.opt.foldenable = true
vim.opt.foldlevel = 9999
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.o.mouse = "a"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.o.confirm = true
vim.o.statusline = "%f"
vim.o.termguicolors = true
vim.cmd.colorscheme("slate")
vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)

-- undo points at punctuation, so `u` doesn't eat a whole insert session
for _, ch in ipairs({ " ", ",", ".", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}" }) do
	vim.keymap.set("i", ch, ch .. "<C-g>u", { noremap = true })
end

-------------
-- KEYMAPS --
-------------
vim.keymap.set("n", "j", "gj", { noremap = true })
vim.keymap.set("n", "k", "gk", { noremap = true })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

local prefixes = {}
local function keymap_prefix(prefix_key, prefix_desc)
	prefixes[prefix_key] = prefix_desc
	return function(key, fn, desc, opts)
		opts = opts or {}
		vim.keymap.set(opts.mode or "n", "<leader>" .. prefix_key .. key, fn, {
			desc = prefix_desc .. " " .. desc,
			buffer = opts.buffer,
		})
	end
end

local cmap = keymap_prefix("c", "[C]ode")
local dmap = keymap_prefix("d", "[D]iagnostic")
local fmap = keymap_prefix("f", "[F]ind")
local hmap = keymap_prefix("h", "[H]over")
local rmap = keymap_prefix("r", "[R]eplace")

dmap("o", vim.diagnostic.open_float, "[O]pen")
dmap("p", function()
	vim.diagnostic.jump({ count = -1 })
end, "[P]rev")
dmap("n", function()
	vim.diagnostic.jump({ count = 1 })
end, "[N]ext")

rmap("s", ":s/\\%V", "[S]election", { mode = "v" })
rmap("l", ":s/", "[L]ine", { mode = "v" })

cmap("f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, "[F]ormat")
cmap("c", function()
	vim.api.nvim_feedkeys(vim.keycode("a<C-Space>"), "t", false)
end, "[C]omplete")

vim.diagnostic.config({ virtual_text = true })

-------------
-- PLUGINS --
-------------
-- Hooks must be registered before add(), so they fire on first install.
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind, path = ev.data.spec.name, ev.data.kind, ev.data.path
		if kind ~= "install" and kind ~= "update" then
			return
		end
		if name == "fzf" then
			vim.system({ "./install", "--bin" }, { cwd = path }):wait()
		elseif name == "nvim-treesitter" and kind == "update" then
			-- plugin/ files aren't sourced yet during init, so :TSUpdate doesn't exist
			vim.cmd.packadd("nvim-treesitter")
			pcall(function()
				require("nvim-treesitter").update():wait(300000)
			end)
		end
	end,
})

local function gh(x)
	return "https://github.com/" .. x
end

vim.pack.add({
	{ src = gh("Saghen/blink.cmp"), version = vim.version.range("1") },
	gh("neovim/nvim-lspconfig"),
	gh("mason-org/mason.nvim"),
	gh("mason-org/mason-lspconfig.nvim"),
	{ src = gh("nvim-treesitter/nvim-treesitter"), version = "main" },
	gh("stevearc/conform.nvim"),
	gh("ibhagwan/fzf-lua"),
	gh("junegunn/fzf"),
	gh("folke/which-key.nvim"),
	gh("windwp/nvim-autopairs"),
	gh("rmagatti/goto-preview"),
	gh("rmagatti/logger.nvim"),
	gh("j-hui/fidget.nvim"),
	gh("milanglacier/minuet-ai.nvim"),
}, { confirm = false })

-- fzf's binary is built into the plugin dir by the PackChanged hook above.
vim.env.PATH = vim.fs.joinpath(vim.fn.stdpath("data"), "site/pack/core/opt/fzf/bin") .. ":" .. vim.env.PATH

---------------
-- BOOTSTRAP --
---------------
local config_dir = vim.fn.stdpath("config")

if vim.fn.isdirectory(config_dir .. "/node_modules") == 0 and vim.fn.executable("npm") == 1 then
	local cmd = vim.fn.filereadable(config_dir .. "/package-lock.json") == 1 and "ci" or "install"
	vim.notify("nvim: installing prettier…")
	vim.system(
		{ "npm", cmd, "--no-audit", "--no-fund" },
		{ cwd = config_dir },
		vim.schedule_wrap(function(r)
			vim.notify(r.code == 0 and "nvim: prettier ready" or ("nvim: npm failed\n" .. r.stderr))
		end)
	)
end

vim.schedule(function()
	local missing = vim.tbl_filter(function(exe)
		return vim.fn.executable(exe) == 0
	end, { "git", "node", "npm", "deno", "php", "python3", "cc", "rg", "curl", "ollama" })
	if #missing > 0 then
		vim.notify("nvim: missing toolchains: " .. table.concat(missing, ", "), vim.log.levels.WARN)
	end
end)

local function env(name, default)
	local v = os.getenv(name)
	if v == nil or v == "" then
		return default
	end
	return tonumber(v) or v
end

local LLM = {
	model = env("NVIM_LLM_MODEL", "qwen2.5-coder:1.5b-base"),
	endpoint = env("NVIM_LLM_ENDPOINT", "http://localhost:11434/v1/completions"),
	context = env("NVIM_LLM_CONTEXT", 8000),
	max_tokens = env("NVIM_LLM_MAX_TOKENS", 256),
	timeout = env("NVIM_LLM_TIMEOUT", 5),
	throttle = env("NVIM_LLM_THROTTLE", 200),
	debounce = env("NVIM_LLM_DEBOUNCE", 150),
	temperature = env("NVIM_LLM_TEMPERATURE", 0.1),
	top_p = env("NVIM_LLM_TOP_P", 0.9),
}

if vim.fn.executable("ollama") == 1 and LLM.endpoint:match("^http://localhost") then
	vim.system(
		{ "ollama", "list" },
		{ text = true },
		vim.schedule_wrap(function(r)
			if r.code ~= 0 or r.stdout:find(LLM.model, 1, true) then
				return
			end
			vim.notify("nvim: pulling " .. LLM.model .. "…")
			vim.system(
				{ "ollama", "pull", LLM.model },
				{},
				vim.schedule_wrap(function(p)
					vim.notify(p.code == 0 and "nvim: " .. LLM.model .. " ready" or "nvim: ollama pull failed")
				end)
			)
		end)
	)
end

---------
-- LSP --
---------
local function php_version()
	local pinned = os.getenv("PHP_VERSION")
	if pinned or vim.fn.executable("php") == 0 then
		return pinned
	end
	local out = vim.fn.systemlist("php --version")[1]
	return out and out:match("PHP%s+([%d%.]+)") or nil
end

local servers = {
	"cssls",
	"html",
	"jsonls",
	"bashls",
	"tailwindcss",
	"emmet_language_server",
	lua_ls = {
		settings = { Lua = { diagnostics = { globals = { "vim" }, disable = { "missing-fields" } } } },
	},
	denols = {
		-- deno owns anything that isn't demonstrably a node project (incl. orphan files)
		root_dir = function(bufnr, on_dir)
			local p = project(vim.api.nvim_buf_get_name(bufnr))
			if not p or p.kind ~= "node" then
				on_dir(p and p.root or vim.fn.getcwd())
			end
		end,
	},
	vtsls = {
		root_dir = function(bufnr, on_dir)
			local p = project(vim.api.nvim_buf_get_name(bufnr))
			if p and p.kind == "node" then
				on_dir(p.root)
			end
		end,
	},
	intelephense = {
		settings = {
			intelephense = {
				environment = { phpVersion = php_version() },
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
					"memcache",
					"memcached",
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
				},
			},
		},
	},
	basedpyright = {},
	ruff = {
		on_attach = function(client)
			client.server_capabilities.hoverProvider = false
			client.server_capabilities.definitionProvider = false
		end,
	},
}

local normalized = {}
for k, v in pairs(servers) do
	if type(k) == "number" then
		normalized[v] = {}
	else
		normalized[k] = v
	end
end
servers = normalized

local ensure_installed = vim.tbl_keys(servers)

-- gdscript's "server" is Godot itself, on TCP :6005. Never install it.
servers.gdscript = {}

require("mason").setup()

local function ensure_tool(registry, name, on_ready)
	local ok, pkg = pcall(registry.get_package, name)
	if not ok then
		return
	end
	if pkg:is_installed() then
		return on_ready and on_ready()
	end
	if on_ready then
		pkg:once("install:success", vim.schedule_wrap(on_ready))
	end
	pkg:install()
end

----------------
-- COMPLETION --
----------------
require("blink.cmp").setup({
	keymap = { preset = "super-tab" },
	sources = {
		default = { "lsp", "snippets", "path", "buffer", "minuet" },
		providers = {
			minuet = {
				module = "minuet.blink",
				name = "minuet",
				async = true,
				timeout_ms = 3000,
				score_offset = 100,
			},
			snippets = {
				opts = {
					search_paths = { vim.fs.joinpath(config_dir, "snippets") },
					extended_filetypes = {
						typescriptreact = { "typescript", "javascript", "html" },
						javascriptreact = { "javascript", "html" },
						typescript = { "javascript" },
					},
				},
			},
			lsp = {
				fallbacks = { "buffer" },
				-- solid-js exports server-only entrypoints that are never what you want
				transform_items = function(_, items)
					return vim.tbl_filter(function(item)
						local text = table.concat({
							item.label or "",
							item.detail or "",
							item.labelDetails and item.labelDetails.description or "",
						}, " ")
						return not text:match("solid%-js/.*server")
					end, items)
				end,
			},
		},
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
	fuzzy = { implementation = "lua", sorts = { "sort_text", "score", "label" } },
	signature = { enabled = true },
})

require("minuet").setup({
	provider = "openai_fim_compatible",
	n_completions = 1,
	context_window = LLM.context,
	request_timeout = LLM.timeout,
	throttle = LLM.throttle,
	debounce = LLM.debounce,
	add_single_line_entry = true,
	notify = "error",
	provider_options = {
		openai_fim_compatible = {
			name = "ollama",
			end_point = LLM.endpoint,
			model = LLM.model,
			api_key = "TERM",
			optional = { max_tokens = LLM.max_tokens, top_p = LLM.top_p, temperature = LLM.temperature },
		},
	},
})

vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
for name, server in pairs(servers) do
	vim.lsp.config(name, server)
end

require("mason-lspconfig").setup({
	ensure_installed = ensure_installed,
	automatic_enable = ensure_installed,
})

vim.lsp.enable("gdscript")

----------------
-- TREESITTER --
----------------
local parsers = {
	"typescript",
	"tsx",
	"javascript",
	"css",
	"html",
	"json",
	"bash",
	"php",
	"gdscript",
	"python",
	"lua",
}

local function install_parsers()
	local installed = require("nvim-treesitter.config").get_installed("parsers")
	local missing = vim.tbl_filter(function(p)
		return not vim.tbl_contains(installed, p)
	end, parsers)
	if #missing > 0 then
		require("nvim-treesitter").install(missing)
	end
end

vim.schedule(function()
	local registry = require("mason-registry")
	registry.refresh(function()
		for _, name in ipairs({ "stylua", "shfmt", "gdtoolkit" }) do
			ensure_tool(registry, name)
		end
		ensure_tool(registry, "tree-sitter-cli", install_parsers)
	end)
end)

----------------
-- FORMATTING --
----------------
local conform = require("conform")

conform.formatters.prettier = {
	command = vim.fs.joinpath(config_dir, "node_modules/.bin/prettier"),
	prepend_args = function(_, ctx)
		return vim.bo[ctx.buf].filetype == "php"
				and { "--plugin", vim.fs.joinpath(config_dir, "node_modules/@prettier/plugin-php") }
			or {}
	end,
}

local function js(bufnr)
	local p = project(vim.api.nvim_buf_get_name(bufnr))
	return (p and p.kind == "deno") and { "deno_fmt" } or { "prettier" }
end

conform.setup({
	formatters_by_ft = {
		javascript = js,
		javascriptreact = js,
		typescript = js,
		typescriptreact = js,
		json = js,
		jsonc = js,
		css = { "prettier" },
		html = { "prettier" },
		markdown = { "prettier" },
		php = { "prettier" },
		python = { "ruff_organize_imports", "ruff_format" },
		sh = { "shfmt" },
		bash = { "shfmt" },
		gdscript = { "gdformat" },
		lua = { "stylua" },
	},
	format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
})

--------------
-- AUTOCMDS --
--------------
local function augroup(name)
	return vim.api.nvim_create_augroup(name, { clear = true })
end

vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
	desc = "Save on focus loss",
	group = augroup("autosave"),
	callback = function(ev)
		local b = ev.buf
		if not vim.api.nvim_buf_is_valid(b) or vim.api.nvim_buf_get_name(b) == "" then
			return
		end
		if vim.bo[b].buftype ~= "" or vim.bo[b].readonly or not vim.bo[b].modifiable then
			return
		end
		if not vim.bo[b].modified then
			return
		end
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(b) and vim.bo[b].modified then
				vim.api.nvim_buf_call(b, function()
					vim.cmd("silent! write")
				end)
			end
		end)
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	desc = "Highlighting and folds",
	group = augroup("buffer-options"),
	callback = function(ev)
		pcall(vim.treesitter.start, ev.buf)
		if vim.bo[ev.buf].filetype == "python" then
			vim.opt_local.foldmethod = "indent"
			vim.opt_local.foldexpr = ""
		else
			vim.opt_local.foldmethod = "expr"
			vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		end
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = augroup("lsp-attach"),
	callback = function(ev)
		local buf = ev.buf
		local fzf = require("fzf-lua")

		fmap("d", fzf.lsp_definitions, "[D]efinition", { buffer = buf })
		fmap("r", fzf.lsp_references, "[R]eferences", { buffer = buf })
		fmap("I", fzf.lsp_implementations, "[I]mplementations", { buffer = buf })
		fmap("T", fzf.lsp_typedefs, "[T]ype definitions", { buffer = buf })
		fmap("s", fzf.lsp_document_symbols, "[S]ymbols (Document)", { buffer = buf })
		fmap("S", fzf.lsp_live_workspace_symbols, "[S]ymbols (Workspace)", { buffer = buf })
		fmap("D", vim.lsp.buf.declaration, "[D]eclaration", { buffer = buf })

		rmap("n", vim.lsp.buf.rename, "[N]ame", { buffer = buf })
		cmap("a", vim.lsp.buf.code_action, "[A]ction", { buffer = buf, mode = { "n", "x" } })
		hmap("d", vim.lsp.buf.hover, "[D]ocumentation", { buffer = buf })

		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
			cmap("h", function()
				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
			end, "Inlay [H]ints", { buffer = buf })
		end
	end,
})

-----------
-- SETUP --
-----------
local fzf = require("fzf-lua")
local ignore = {
	-- package management
	"vendor",
	"node_modules",
	-- version control
	".git",
	-- godot
	".godot",
	"*.import",
	"*.uid",
	-- media
	"*.svg",
	"*.png",
	"*.jpg",
	"*.wav",
	"*.mp3",
}
local excludes = vim.iter(ignore)
	:map(function(g)
		return "--exclude '" .. g .. "'"
	end)
	:join(" ")
fzf.setup({
	file_icons = false,
	git_icons = false,
	lsp = { code_actions = { previewer = false } },
	files = { fd_opts = "--color=never --type f --type l " .. excludes },
})
fzf.register_ui_select()
require("nvim-autopairs").setup({})
require("fidget").setup({})

local preview = require("goto-preview")
preview.setup({})
hmap("p", preview.goto_preview_definition, "[P]review")
hmap("q", preview.close_all_win, "[Q]uit")

fmap("f", function()
	fzf.files({ hidden = true, no_ignore = true })
end, "[F]iles")
fmap("g", fzf.live_grep, "[G]rep")
fmap("b", fzf.buffers, "[B]uffers")
fmap("o", fzf.oldfiles, "[O]ld")
fmap("n", fzf.resume, "[N]ext")
fmap(".", fzf.blines, "[.] Here")
dmap("l", fzf.diagnostics_document, "[L]ist")

local wk = require("which-key")
wk.setup({ plugins = { presets = { motions = false } }, icons = { keys = { Esc = "⨉ ", BS = "↩ " } } })
for key, description in pairs(prefixes) do
	wk.add({ { "<leader>" .. key, group = description } })
end
