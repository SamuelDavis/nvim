local lsp = require('lsp-zero').preset({})

lsp.on_attach(function(_, bufnr)
  lsp.default_keymaps({buffer = bufnr})
  local opts = {buffer = bufnr, remap = false}

  -- find definition
  vim.keymap.set("n", "<leader>cd", function() vim.lsp.buf.definition() end, opts)
  -- find usages
  vim.keymap.set("n", "<leader>cu", function() vim.lsp.buf.references() end, opts)
  -- show hover
  vim.keymap.set("n", "<leader>ch", function() vim.lsp.buf.hover() end, opts)
  -- next diagnostic
  vim.keymap.set("n", "<leader>cp]", function() vim.diagnostic.goto_next() end, opts)
  -- prev diagnostic
  vim.keymap.set("n", "<leader>cp[", function() vim.diagnostic.goto_prev() end, opts)
  -- rename symbol
  vim.keymap.set("n", "<leader>cr", function() vim.lsp.buf.rename() end, opts)
  -- code action
  vim.keymap.set("n", "<leader>ca", function() vim.lsp.buf.code_action() end, opts)
end)

-- (Optional) Configure lua language server for neovim
require('lspconfig').lua_ls.setup(lsp.nvim_lua_ls())

lsp.setup()

-- Make sure you setup `cmp` after lsp-zero

local cmp = require('cmp')
local cmp_action = require('lsp-zero').cmp_action()

cmp.setup({
  mapping = {
    -- `Enter` key to confirm completion
    ['<Tab>'] = cmp.mapping.confirm({select = false}),

    -- Ctrl+Space to trigger completion menu
    ['<C-Tab>'] = cmp.mapping.complete(),

    -- Navigate between snippet placeholder
    ['<C-f>'] = cmp_action.luasnip_jump_forward(),
    ['<C-b>'] = cmp_action.luasnip_jump_backward(),
  }
})
