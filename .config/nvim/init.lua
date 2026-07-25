
-- leader
vim.g.mapleader = " "

-- search
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- statusline
vim.opt.laststatus = 3

-- indentation
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4

-- scrolling
vim.opt.scrolloff = 3

-- cursor
vim.opt.cursorline = true
vim.opt.updatetime = 250

-- noise control
vim.opt.visualbell = true
vim.opt.shortmess:append("I")

-- security
vim.opt.modeline = false

-- line numbers
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"

-- clipboard
vim.opt.clipboard = "unnamedplus"

-- persistent undo
vim.opt.undofile = true

-- color scheme
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.cmd.colorscheme("default")

-- keymaps
vim.keymap.set("n", "<leader>h", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
