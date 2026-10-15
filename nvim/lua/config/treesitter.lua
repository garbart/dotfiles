-- Tree-sitter parsers for syntax highlighting and folding.
--
-- install.sh builds them during setup:
--   nvim --headless "+lua require('config.treesitter').install():wait(600000)" +qa
-- editing.lua builds any missing ones in the background on start.

local M = {}

M.parsers = {
  'bash',
  'c',
  'cmake',
  'cpp',
  'diff',
  'dockerfile',
  'git_config',
  'gitcommit',
  'gitignore',
  'json',
  'lua',
  'make',
  'markdown',
  'markdown_inline',
  'python',
  'toml',
  'vim',
  'vimdoc',
  'yaml',
}

-- Building a parser needs the tree-sitter CLI and a C compiler.
function M.available()
  return vim.fn.executable('tree-sitter') == 1 and vim.fn.executable('cc') == 1
end

function M.install()
  return require('nvim-treesitter').install(M.parsers)
end

return M
