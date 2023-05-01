vim.g.mapleader = ","
vim.g.prettier = {}
vim.g.prettier.autoformat = 1
vim.g.prettier.autoformat_require_pragma = 0

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

local commands = {
    colorscheme = "slate",
    syntax = "on",
}

for command, value in pairs(commands) do
    vim.cmd(command .. " " .. value)
end

local plug_file = home_directory .. "/nvim/site/autoload/plug.vim"
if not file_exists(plug_file) then
    os.execute(
        "curl -fLo " ..
        plug_file .. " --create-dirs " .. "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
    )
end

local plugins = {
    -- fuzzy-finder
    ["junegunn/fzf"] = { ["do"] = function()
        vim.call("fzf#install")
    end },
    ["junegunn/fzf.vim"] = false,
    -- syntax-highlighting
    ["nvim-treesitter/nvim-treesitter"] = { run = function()
        vim.cmd("TSUpdate")
    end },
    -- undo diff
    ["mbbill/undotree"] = false,
    -- LSP Support
    ["neovim/nvim-lspconfig"] = false,
    ["williamboman/mason.nvim"] = { ["do"] = function()
        vim.cmd("MasonUpdate")
    end },
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

local lsp = require("lsp-zero").preset({})

lsp.on_attach(function(client, bufnr)
    lsp.default_keymaps({ buffer = bufnr })
end)

-- (Optional) Configure lua language server for neovim
require("lspconfig").lua_ls.setup(lsp.nvim_lua_ls())

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

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = function(ev)
        -- Enable completion triggered by <c-x><c-o>
        vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

        -- Buffer local mappings.
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        local opts = { buffer = ev.buf }
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, opts)
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format { async = true }
        end, opts)
    end,
})

vim.cmd [[autocmd BufWritePre * :Prettier]]

