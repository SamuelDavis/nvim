local function find_root()
	local path = vim.fn.expand("%:p:h")

	local arg = vim.fn.argv(0)
	if vim.fn.isdirectory(arg) then
		path = arg
	end

	local search = vim.fs.find(
		{ ".git", "package.json", "composer.json", "requirements.txt" },
		{ upward = true, path = path }
	)

	if search[1] then
		path = vim.fs.dirname(search[1])
	end

	return path
end

-------------
-- OPTIONS --
-------------
vim.g.mapleader = ","
vim.g.maplocalleader = vim.g.mapleader
vim.g.have_nerd_font = false
vim.opt.number = true
vim.opt.mouse = "a"
vim.opt.showmode = false
vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.opt.inccommand = "split"
vim.opt.cursorline = true
vim.opt.scrolloff = 10
vim.opt.colorcolumn = "80"
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldlevel = 9999
vim.cmd.colorscheme("slate")


-------------
-- KEYMAPS --
-------------
local function map(keys, fn, desc, opts, mode)
	opts = opts or {}
	opts.desc = desc
	mode = mode or "n"
	vim.keymap.set(mode, "<leader>" .. keys, fn, opts)
end

local function currymap(prefixed_keys, prefixed_desc)
	return function(keys, fn, desc, opts, mode)
		keys = prefixed_keys .. keys
		desc = prefixed_desc .. " " .. desc
		mode = mode or "n"
		map(keys, fn, desc, opts)
	end
end

local dmap = currymap("d", "[D]iagnostic")
local fmap = currymap("f", "[F]ind")

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

dmap("o", vim.diagnostic.open_float, "[O]pen Float")
dmap("p", vim.diagnostic.get_prev, "[P]revious")
dmap("n", vim.diagnostic.get_next, "[N]ext")
dmap("l", vim.diagnostic.setloclist, "[L]ist")

-------------
-- PLUGINS --
-------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		error("Error cloning lazy.nvim:\n" .. out)
	end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
	{ "windwp/nvim-autopairs", opts = {} },
	{ "tpope/vim-sleuth" },
	{
		"folke/which-key.nvim",
		event = "VimEnter",
		opts = {
			icons = {
				keys = {
					Up = "<Up> ",
					Down = "<Down> ",
					Left = "<Left> ",
					Right = "<Right> ",
					C = "<C-…> ",
					M = "<M-…> ",
					D = "<D-…> ",
					S = "<S-…> ",
					CR = "<CR> ",
					Esc = "<Esc> ",
					ScrollWheelDown = "<ScrollWheelDown> ",
					ScrollWheelUp = "<ScrollWheelUp> ",
					NL = "<NL> ",
					BS = "<BS> ",
					Space = "<Space> ",
					Tab = "<Tab> ",
					F1 = "<F1>",
					F2 = "<F2>",
					F3 = "<F3>",
					F4 = "<F4>",
					F5 = "<F5>",
					F6 = "<F6>",
					F7 = "<F7>",
					F8 = "<F8>",
					F9 = "<F9>",
					F10 = "<F10>",
					F11 = "<F11>",
					F12 = "<F12>",
				},
			},
			spec = {
				{ "<leader>c", group = "[C]ode",      mode = { "n", "x" } },
				{ "<leader>d", group = "[D]iagnostic" },
				{ "<leader>f", group = "[F]ind" },
				{ "<leader>t", group = "[T]oggle" },
				{ "<leader>r", group = "[R]ename" },
				{ "<leader>c", group = "[C]ode" },
				{ "<leader>h", "[H]over" },
			},
		},
	},
	{
		"nvim-telescope/telescope.nvim",
		event = "VimEnter",
		branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-ui-select.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
		},
		config = function()
			local telescope = require("telescope")
			local builtin = require("telescope.builtin")
			telescope.setup({
				defaults = {
					file_ignore_patterns = {
						"venv",
						"__pycache__",
						"node_modules",
						"vendor",
					},
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
				},
			})
			pcall(telescope.load_extension, "fzf")
			pcall(telescope.load_extension, "ui-select")

			local function current_file()
				builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
					winblend = 10,
					previewer = false,
				}))
			end
			local function open_files()
				builtin.live_grep({
					grep_open_files = true,
					prompt_title = "Live Grep in Open Files",
				})
			end

			dmap("l", builtin.diagnostics, "[L]ist")
			fmap("h", builtin.help_tags, "[H]elp")
			fmap("k", builtin.keymaps, "[K]eymaps")
			fmap("f", builtin.find_files, "[F]iles")
			fmap("t", builtin.builtin, "[T]elescope")
			fmap("g", builtin.live_grep, "[G]rep")
			fmap("c", builtin.resume, "[C]ontinue")
			fmap("b", builtin.buffers, "[B]uffers")
			fmap("o", builtin.oldfiles, "[O]ld Files")
			fmap(".", current_file, "[.] Current File")
			fmap("..", open_files, "[..] Open Files")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		main = "nvim-treesitter.configs",
		opts = {
			auto_install = true,
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = { "ruby" },
			},
			indent = {
				enable = true,
				disable = { "ruby", "gdscript" },
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"hrsh7th/nvim-cmp",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-cmdline",
			{ "williamboman/mason.nvim", config = true },
			"williamboman/mason-lspconfig.nvim",
			"WhoIsSethDaniel/mason-tool-installer.nvim",
		},
		config = function()
			local cmp = require("cmp")
			local lsp = require("lspconfig")
			local tools = require("mason-tool-installer")
			local mason = require("mason-lspconfig")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			local acceptSelection = cmp.mapping(function(fallback)
				if cmp.visible() then
					local entry = cmp.get_selected_entry()
					if not entry then
						cmp.select_next_item({
							behavior = cmp.SelectBehavior
							    .Select
						})
					end
					cmp.confirm()
				else
					fallback()
				end
			end, { "i", "s", "c", })

			cmp.setup.cmdline(":", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = "path" },
					{ name = "cmdline" },
				}),
			})

			cmp.setup({
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "buffer" },
					{ name = "path" },
					{ name = "cmdline" },
				}),
				mapping = {
					["<Tab>"] = acceptSelection,
					["<CR>"] = acceptSelection,
				},
			})

			local servers = {
				lua_ls = {
					settings = {
						Lua = {
							diagnostics = {
								globals = { "vim" },
							},
						},
					},
				},
				intelephense = {},
				biome = {
					settings = {
						biome = {
							enableLinting = true,
							enableFormatting = true,
						},
					},
				},
			}

			local ensure_installed = vim.tbl_keys(servers or {})
			tools.setup({ ensure_installed = ensure_installed })
			mason.setup({
				handlers = {
					function(name)
						local server = servers[name] or {}
						server.capabilities = vim.tbl_deep_extend("force", capabilities,
							vim.lsp.protocol.make_client_capabilities(),
							server.capabilities or {})
						server.root_dir = server.root_dir or find_root()
						lsp[name].setup(server)
					end,
				},
			})

			local group = vim.api.nvim_create_augroup("lsp-attach", { clear = true })
			vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				callback = function(event)
					local builtin = require("telescope.builtin")
					fmap("d", builtin.lsp_definitions, "[D]efinition")
					fmap("r", builtin.lsp_references, "[R]eferences")
					fmap("I", builtin.lsp_implementations, "[I]mplementations")
					fmap("T", builtin.lsp_type_definitions, "[T]ype definitions")
					fmap("sw", builtin.lsp_dynamic_workspace_symbols, "[S]ymbols (Workspace)")
					fmap("sd", builtin.lsp_document_symbols, "[S]ymbols ([D]ocument)")
					fmap("D", vim.lsp.buf.declaration, "[D]eclaration")

					map("rn", vim.lsp.buf.rename, "[R]e[N]ame")
					map("ca", vim.lsp.buf.code_action, "[C]ode [A]ction", {}, { "n", "x" })
					map("cf", vim.lsp.buf.format, "[C]ode [F]ormat")
					map("hd", vim.lsp.buf.hover, "[H]over [D]ocumentation")

					local client = vim.lsp.get_client_by_id(event.data.client_id)
					if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
						local highlight_augroup =
						    vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
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
							group = vim.api.nvim_create_augroup("lsp-detach",
								{ clear = true }),
							callback = function(event2)
								vim.lsp.buf.clear_references()
								vim.api.nvim_clear_autocmds({
									group = "lsp-highlight",
									buffer = event2.buf,
								})
							end,
						})
					end

					if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
						map("th", function()
							vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({
								bufnr =
								    event.buf
							}))
						end, "[T]oggle Inlay [H]ints")
					end

					if client and client.supports_method(vim.lsp.protocol.format) then
						vim.api.nvim_create_autocmd("BufWritePre", {
							group = vim.api.nvim_create_augroup("lsp-format",
								{ clear = true }),
							callback = function()
								local pos = vim.api.nvim_win_get_cursor(0)
								local success, err = pcall(vim.lsp.buf.format,
									{ async = false })
								if success then
									vim.api.nvim_win_set_cursor(0, pos)
								else
									vim.notify("Formatter failed: " .. tostring(err),
										vim.log.levels.ERROR)
								end
							end,
						})
					end
				end,
			})
		end
	},
})

--------------
-- AUTOCMDS --
--------------
vim.api.nvim_create_autocmd("VimEnter", {
	desc = "Set CWD to opened file/folder",
	group = vim.api.nvim_create_augroup("chdir-on-start", { clear = true }),
	callback = function()
		vim.cmd("cd " .. find_root())
	end,
})

local autosave_group = vim.api.nvim_create_augroup("autosave", { clear = true })
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
	desc = "Autosave on focus lost",
	group = autosave_group,
	callback = function()
		if vim.bo.modified then
			vim.cmd("silent! write")
		end
	end,
})
