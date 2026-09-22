-- Minimal nvim config: only worktrunk.nvim loaded, no user config.
vim.opt.rtp:append(vim.fn.getcwd())

vim.o.termguicolors = true
vim.o.swapfile = false
vim.o.number = true

require("worktrunk").setup({})
vim.notify("worktrunk.nvim loaded", vim.log.levels.INFO)
