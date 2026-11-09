-- project dir: enclosing git repo, else the opened directory, else the opened file's directory
-- (nvim.sh mounts by the same rule)
local start_arg = vim.fn.argv(0)
if start_arg ~= "" then
	local path = vim.fn.fnamemodify(start_arg, ":p")
	local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
	local project_dir = vim.fs.root(dir, ".git") or dir
	if vim.fn.isdirectory(project_dir) == 1 then
		vim.cmd.cd(project_dir)
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
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
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
-- container (see nvim.sh)
if vim.env.NVIM_CONTAINER then
	-- no host clipboard access; copy via terminal escape, paste via terminal
	local osc52 = require("vim.ui.clipboard.osc52")
	local function paste_unnamed()
		return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
	end
	vim.g.clipboard = {
		name = "OSC 52",
		copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
		paste = { ["+"] = paste_unnamed, ["*"] = paste_unnamed },
	}
	-- suspending freezes the container without returning control to the host shell
	vim.keymap.set({ "n", "v" }, "<C-z>", "<Nop>")
	vim.api.nvim_create_user_command("SuspendDisabled", function()
		vim.notify("suspend is disabled inside the container", vim.log.levels.WARN)
	end, { bang = true, nargs = "*" })
	for _, abbreviation in ipairs({ "sus", "susp", "suspe", "suspen", "suspend", "st", "sto", "stop" }) do
		vim.keymap.set("ca", abbreviation, function()
			local is_whole_command = vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == abbreviation
			return is_whole_command and "SuspendDisabled" or abbreviation
		end, { expr = true })
	end
	-- single-file bind mounts can't be replaced by rename-on-write
	vim.opt.backupcopy = "yes"
end
-- clipboard
vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)
-- less destructive undos (brackets omitted: nvim-autopairs owns them)
local undopoints = { " ", ",", ".", "!", "?", ";", ":" }
for _, ch in ipairs(undopoints) do
	vim.keymap.set("i", ch, ch .. "<C-g>u")
end
-- buffer metadata
vim.o.statusline = "%f %m%r%=%l:%c"

-------------
-- KEYMAPS --
-------------
vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

local function map(key, fn, desc, mode, buffer)
	vim.keymap.set(mode or "n", "<leader>" .. key, fn, { desc = desc, buffer = buffer })
end

local prefixes = {}
local function keymap_prefix(prefix_key, prefix_desc)
	prefixes[prefix_key] = prefix_desc
	return function(key, fn, desc, mode, buffer)
		map(prefix_key .. key, fn, prefix_desc .. " " .. desc, mode, buffer)
	end
end

local function which_key_groups()
	local groups = {}
	for key, description in pairs(prefixes) do
		table.insert(groups, { "<leader>" .. key, group = description })
	end
	return groups
end

local dmap = keymap_prefix("d", "[D]iagnostic")
local fmap = keymap_prefix("f", "[F]ind")
local rmap = keymap_prefix("r", "[R]eplace")
local cmap = keymap_prefix("c", "[C]ode")
local hmap = keymap_prefix("h", "[H]over")

dmap("o", vim.diagnostic.open_float, "[O]pen")
dmap("p", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, "[P]rev")
dmap("n", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, "[N]ext")

rmap("s", ":s/\\%V", "[S]election", "v")
rmap("l", ":s/", "[L]ine", "v")

cmap("f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, "[F]ormat")

---------
-- LLM --
---------
local uv = vim.uv or vim.loop
local function resolve_ipv4(hostname)
	local addresses = uv.getaddrinfo(hostname, nil, { family = "inet" })
	return addresses and addresses[1] and addresses[1].addr or hostname
end
-- services on the host (ollama, godot) are unreachable via loopback from a non-host-networked container
local host_addr = resolve_ipv4(os.getenv("NVIM_HOST_ADDR") or "127.0.0.1")

local function ping_ollama(host, port, timeout_ms)
	host = host or host_addr
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
local ollama_available = model ~= nil and ping_ollama()

-------------
-- PLUGINS --
-------------
local function detect_php_version()
	local env_version = os.getenv("PHP_VERSION")
	if env_version or vim.fn.executable("php") == 0 then
		return env_version
	end
	return vim.fn.systemlist({ "php", "--version" })[1]:match("PHP%s+([%d%.]+)")
end

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
	"tailwindcss",
	pyright = {
		-- read the project venv's packages directly; its interpreter may not exist here (container, other OS)
		before_init = function(_, config)
			local site_packages = vim.fn.glob(config.root_dir .. "/.venv/lib/python3*/site-packages", true, true)
			if #site_packages == 0 then
				return
			end
			-- mutate in place: the client already holds a reference to config.settings
			local python = config.settings.python or {}
			config.settings.python = python
			python.analysis = python.analysis or {}
			python.analysis.extraPaths = site_packages
		end,
	},
	intelephense = {
		before_init = function(_, config)
			config.settings.intelephense.environment = { phpVersion = detect_php_version() }
		end,
		settings = {
			intelephense = {
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
	"emmet_language_server",
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
local tools = {
	-- formatters
	"stylua",
	"prettierd",
	"isort",
	"black",
	"gdtoolkit",
	"pint",
	-- builds nvim-treesitter parsers
	"tree-sitter-cli",
}
local ensure_installed = vim.iter({ vim.tbl_keys(servers), tools }):flatten():totable()
servers["gdscript"] = {
	cmd = vim.lsp.rpc.connect(host_addr, tonumber(os.getenv("GDScript_Port") or "6005")),
}

local function config_telescope()
	local telescope = require("telescope")

	local file_ignore_patterns = vim.iter({
		--misc
		{ "%.ttf$", "%.git/", "%.lock$" },
		-- audio
		{ "%.mp3$", "%.wav$" },
		-- images
		{ "%.png$", "%.swf$", "%.svg$" },
		-- godot
		{ "%.uid$", "%.import$", "%.db$", "%.tscn$", "%.tres$", "%.godot$" },
		-- vendor
		{ "package%-lock%.json$", "node_modules/", "vendor/", "%.venv/" },
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

	-- Skip heavy dirs at the finder so they're never walked, not just filtered.
	local find_command = {
		"rg",
		"--files",
		"--hidden",
		"--no-ignore",
		"--glob=!**/.git/*",
		"--glob=!**/node_modules/*",
		"--glob=!**/vendor/*",
		"--glob=!**/.venv/*",
		"--glob=!**/dist/*",
	}

	local builtin = require("telescope.builtin")
	dmap("l", builtin.diagnostics, "[L]ist")
	fmap("f", function()
		builtin.find_files({ find_command = find_command })
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
			implementation = "prefer_rust_with_warning",
			sorts = { "sort_text", "score", "label" },
		},
		signature = { enabled = true },
	})
end

local function config_treesitter()
	local treesitter = require("nvim-treesitter")
	local indent_disabled = { gdscript = true }
	local available_parsers = treesitter.get_available()

	local function attach(buf, lang)
		if not vim.api.nvim_buf_is_valid(buf) or not pcall(vim.treesitter.start, buf, lang) then
			return
		end
		if not indent_disabled[lang] then
			vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end
	end

	vim.api.nvim_create_autocmd("FileType", {
		desc = "Start treesitter, installing parser if missing",
		group = vim.api.nvim_create_augroup("Treesitter", { clear = true }),
		callback = function(ev)
			local lang = vim.treesitter.language.get_lang(ev.match)
			if not lang then
				return
			end
			if vim.treesitter.language.add(lang) then
				attach(ev.buf, lang)
				return
			end
			if vim.fn.executable("tree-sitter") == 1 and vim.tbl_contains(available_parsers, lang) then
				treesitter.install(lang):await(vim.schedule_wrap(function()
					attach(ev.buf, lang)
				end))
			end
		end,
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
			spec = which_key_groups(),
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
		config = config_telescope,
	},
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			{ "mason-org/mason-lspconfig.nvim", opts = { automatic_enable = false } },
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
		"saghen/blink.cmp",
		version = "1.*",
		config = config_blink,
	},
	{
		"milanglacier/minuet-ai.nvim",
		enabled = ollama_available,
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			provider = "openai_fim_compatible",
			n_completions = 1,
			context_window = 512,
			provider_options = {
				openai_fim_compatible = {
					api_key = "TERM",
					name = "Ollama",
					end_point = "http://" .. host_addr .. ":11434/v1/completions",
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
		lazy = false,
		build = ":TSUpdate",
		config = config_treesitter,
	},
	{
		"stevearc/conform.nvim",
		cmd = { "ConformInfo" },
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				json = { "prettierd" },
				html = { "prettierd" },
				css = { "prettierd" },
				javascript = { "prettierd" },
				javascriptreact = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				python = { "isort", "black" },
				php = { "pint" },
				gdscript = { "gdformat" },
			},
		},
	},
	{
		"rmagatti/goto-preview",
		dependencies = { "rmagatti/logger.nvim" },
		event = "BufEnter",
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
local function is_editable_file(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and not vim.bo[buf].readonly
		and vim.api.nvim_buf_get_name(buf) ~= ""
end

local autoformat_group = vim.api.nvim_create_augroup("Autoformat", { clear = true })
vim.api.nvim_create_autocmd("BufWritePre", {
	desc = "Format on save",
	group = autoformat_group,
	callback = function(ev)
		if is_editable_file(ev.buf) then
			require("conform").format({ bufnr = ev.buf, timeout_ms = 1000, lsp_format = "fallback" })
		end
	end,
})
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
	desc = "Autosave",
	group = autoformat_group,
	nested = true,
	callback = function(ev)
		if is_editable_file(ev.buf) and vim.bo[ev.buf].modified then
			vim.api.nvim_buf_call(ev.buf, function()
				vim.cmd("silent! update")
			end)
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	desc = "Indent-based folds for python",
	pattern = "python",
	group = vim.api.nvim_create_augroup("PythonFolds", { clear = true }),
	callback = function()
		vim.opt_local.foldmethod = "indent"
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
	callback = function(event)
		local buf = event.buf
		local builtin = require("telescope.builtin")
		fmap("d", builtin.lsp_definitions, "[D]efinition", "n", buf)
		fmap("r", builtin.lsp_references, "[R]eferences", "n", buf)
		fmap("I", builtin.lsp_implementations, "[I]mplementations", "n", buf)
		fmap("T", builtin.lsp_type_definitions, "[T]ype definitions", "n", buf)
		fmap("s", builtin.lsp_dynamic_workspace_symbols, "[S]ymbols (Workspace)", "n", buf)
		fmap("S", builtin.lsp_document_symbols, "[S]ymbols (Document)", "n", buf)
		fmap("D", vim.lsp.buf.declaration, "[D]eclaration", "n", buf)

		rmap("n", vim.lsp.buf.rename, "[N]ame", "n", buf)
		cmap("a", vim.lsp.buf.code_action, "[A]ction", { "n", "x" }, buf)
		hmap("d", vim.lsp.buf.hover, "[D]ocumentation", "n", buf)

		local client = vim.lsp.get_client_by_id(event.data.client_id)

		local optional_autocmds = {
			{
				vim.lsp.protocol.Methods.textDocument_documentHighlight,
				function()
					local highlight_augroup = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
					vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
						buffer = buf,
						group = highlight_augroup,
						callback = vim.lsp.buf.document_highlight,
					})

					vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
						buffer = buf,
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
						local filter = { bufnr = buf }
						vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(filter), filter)
					end, "[T]oggle Inlay [H]ints", "n", buf)
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
