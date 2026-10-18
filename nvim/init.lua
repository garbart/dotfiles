-- Neovim config. install.sh links this directory to ~/.config/nvim.
--
-- A VSCode-like editor with JetBrains colors: file tree, tabs, quick open and
-- search, Cmd shortcuts (via Ghostty), light/dark following the terminal,
-- and for C, C++ and Python navigation, completion and errors by their
-- language servers. Each part lives in lua/config/.

-- nvim-tree replaces netrw, which has to be disabled before anything loads.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.mapleader = ' '

-- Plugins are pinned in nvim-pack-lock.json and installed on first start.
local plugins = {
  'https://github.com/nickkadutskyi/jb.nvim',
  'https://github.com/nvim-tree/nvim-web-devicons',
  'https://github.com/nvim-tree/nvim-tree.lua',
  'https://github.com/akinsho/bufferline.nvim',
  'https://github.com/folke/snacks.nvim',
  'https://github.com/lewis6991/gitsigns.nvim',
  'https://github.com/nvim-treesitter/nvim-treesitter',
  'https://github.com/nvim-mini/mini.pairs',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  'https://github.com/hat0uma/csvview.nvim',
  -- A release, for which blink.cmp has its prebuilt matcher.
  { src = 'https://github.com/saghen/blink.cmp', version = vim.version.range('1') },
}

-- Plugins dropped from the list are deleted from disk: vim.pack would put
-- any plugin it finds there back into the lockfile.
local wanted = {}
for _, plugin in ipairs(plugins) do
  wanted[(type(plugin) == 'table' and plugin.src or plugin):match('[^/]+$')] = true
end
local pack_dir = vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'pack', 'core', 'opt')
for name, type in vim.fs.dir(pack_dir) do
  if type == 'directory' and not wanted[name] then
    vim.fs.rm(vim.fs.joinpath(pack_dir, name), { recursive = true, force = true })
  end
end

vim.pack.add(plugins, { confirm = false })

require('config.options')
require('config.layout')
require('config.bigfile')
require('config.theme')
require('config.ui')
require('config.tree')
require('config.editing')
require('config.markdown')
require('config.autosave')
require('config.lsp')
require('config.completion')
require('config.keymaps')
require('config.modeless')
require('config.scroll')
require('config.menu')
require('config.konami')
