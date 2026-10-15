-- Neovim config. install.sh links this directory to ~/.config/nvim.
--
-- A VSCode-like editor with JetBrains colors: file tree, tabs, quick open and
-- search, Cmd shortcuts (via Ghostty), light/dark following the terminal.
-- No LSP yet. Each part lives in lua/config/.

-- nvim-tree replaces netrw, which has to be disabled before anything loads.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.mapleader = ' '

-- Plugins are pinned in nvim-pack-lock.json and installed on first start.
vim.pack.add({
  'https://github.com/nickkadutskyi/jb.nvim',
  'https://github.com/nvim-tree/nvim-web-devicons',
  'https://github.com/nvim-tree/nvim-tree.lua',
  'https://github.com/nvim-lualine/lualine.nvim',
  'https://github.com/akinsho/bufferline.nvim',
  'https://github.com/folke/snacks.nvim',
  'https://github.com/lewis6991/gitsigns.nvim',
  'https://github.com/nvim-treesitter/nvim-treesitter',
  'https://github.com/nvim-mini/mini.pairs',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
}, { confirm = false })

require('config.options')
require('config.theme')
require('config.ui')
require('config.tree')
require('config.editing')
require('config.keymaps')
require('config.menu')
