local home_directory = os.getenv("HOME")

local function directory_exists(path)
    return os.execute("cd " .. path) == 0
end
local function file_exists(path)
    local file = io.open(path, "r")
    return file ~= nil and io.close(file)
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
    incsearch = true,
}

for option, value in pairs(options) do
    vim.opt[option] = value
end

vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

local commands = {
    colorscheme = "slate",
    syntax = "on",
}

for command, value in pairs(commands) do
    vim.cmd(command .. " " .. value)
end

local sets = { "autochdir" }

for _, value in pairs(sets) do
    vim.cmd("set " .. value)
end

local plug_file = home_directory .. "/.local/share/nvim/site/autoload/plug.vim"
if not file_exists(plug_file) then
    os.execute(
        "curl -fLo " ..
        plug_file .. " --create-dirs " .. "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
    )
end

local plugins = {
    -- fuzzy-finder
    ["nvim-lua/plenary.nvim"] = false,
    ["nvim-telescope/telescope.nvim"] = { ["tag"] = "0.1.1" },
    -- syntax-highlighting
    ["nvim-treesitter/nvim-treesitter"] = {
        ["run"] = function() vim.cmd("TSUpdate") end,
    },
    -- undo diff
    ["mbbill/undotree"] = false,
    -- LSP Support
    ["neovim/nvim-lspconfig"] = false,
    ["williamboman/mason.nvim"] = {
        ["do"] = function() vim.cmd("MasonUpdate") end
    },
    ["williamboman/mason-lspconfig.nvim"] = false,
    -- Autocompletion
    ["hrsh7th/nvim-cmp"] = false,
    ["hrsh7th/cmp-nvim-lsp"] = false,
    ["L3MON4D3/LuaSnip"] = false,
    -- LSP
    ["VonHeikemen/lsp-zero.nvim"] = { branch = "v2.x" },
    -- prettier formatting
    ["prettier/vim-prettier"] = false,
}
vim.call("plug#begin", home_directory .. "/.config/nvim/plugged")
for name, config in pairs(plugins) do
    if config then
        vim.fn["plug#"](name, config)
    else
        vim.fn["plug#"](name)
    end
end
vim.call("plug#end")
vim.cmd("PlugUpdate")

local lsp = require("lsp-zero").preset({})

lsp.on_attach(function(client, bufnr)
    lsp.default_keymaps({ buffer = bufnr })
end)

local LSPConfig = require("lspconfig")
LSPConfig.lua_ls.setup(lsp.nvim_lua_ls())
lsp.setup()

local cmp = require("cmp")
local cmp_action = require("lsp-zero").cmp_action()

cmp.setup({
    preselect = "item",
    completion = { completeopt = "menu,menuone,noinsert" },
    mapping = {
        ["<Tab>"] = cmp_action.luasnip_supertab(),
        ["<S-Tab>"] = cmp_action.luasnip_shift_supertab(),
        ["<C-CR>"] = cmp.mapping.complete(),
        ["<CR>"] = cmp.mapping.confirm(),
    },
})

vim.g.prettier = {
    ["autoformat"] = 1,
    ["autoformat_require_pragma"] = 0,
}
vim.cmd [[autocmd BufWritePre * :Prettier]]

vim.g.mapleader = ","
-- paste+replace without losing yanked value
vim.keymap.set({"n", "v"}, "<leader>p", "\"_dP")
-- yank to system clipboard
vim.keymap.set({"n", "v"}, "<leader>Y", "\"+y")
-- paste from system clipboard
vim.keymap.set("n", "<leader>P", "\"+p")
vim.keymap.set("v", "<leader>P", "\"_d\"+p")
-- view project filetree
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)
local Telescope = require("telescope.builtin")
-- fuzzy-find file
vim.keymap.set("n", "<leader>ff", Telescope.find_files, {})
-- fuzzy-find text (in buffers, {})
vim.keymap.set("n", "<leader>fg", Telescope.live_grep, {})
-- fuzzy-find file in git
vim.keymap.set("n", "<leader>fp", Telescope.git_files, {})
-- fuzzy-find symbol
vim.keymap.set("n", "<leader>fs", Telescope.lsp_dynamic_workspace_symbols, {})
-- find definitions
vim.keymap.set("n", "<leader>fd", Telescope.lsp_definitions, {})
-- find references
vim.keymap.set("n", "<leader>fr", Telescope.lsp_references, {})

-- lsp
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = function(ev)
        vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
        local opts = { buffer = ev.buf }
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "<leader>r", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, opts)
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format { async = true }
        end, opts)
    end,
})
