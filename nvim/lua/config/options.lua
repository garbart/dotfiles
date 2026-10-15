-- Editor options.

-- Absolute line numbers, the current line highlighted.
vim.o.number = true
vim.o.cursorline = true
-- One sign slot: the git change bar (see statuscolumn.lua).
vim.o.signcolumn = 'yes:1'

vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
-- Long lines scroll sideways instead of wrapping, as in VSCode (Markdown
-- wraps, see editing.lua).
vim.o.wrap = false

vim.o.mouse = 'a'
vim.o.splitright = true
vim.o.splitbelow = true
-- Undo history survives restarts.
vim.o.undofile = true
-- Case-insensitive search unless the query has capitals.
vim.o.ignorecase = true
vim.o.smartcase = true
-- Git change marks show up sooner.
vim.o.updatetime = 250

-- Copy and paste go through the system clipboard. Over ssh copying reaches
-- the Mac clipboard via the terminal (OSC 52); pasting with `p` uses the last
-- copy, since reading the clipboard that way makes Ghostty ask every time
-- (Cmd+V pastes from the Mac as usual).
vim.o.clipboard = 'unnamedplus'
if vim.env.SSH_TTY then
  local osc52 = require('vim.ui.clipboard.osc52')
  local function paste()
    return { vim.split(vim.fn.getreg(''), '\n'), vim.fn.getregtype('') }
  end
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = paste, ['*'] = paste },
  }
end

-- The terminal tab is named after the project (the directory nvim works in),
-- like the VSCode window.
vim.o.title = true
vim.o.titlestring = "%{fnamemodify(getcwd(), ':t')}"

-- Rounded corners on every floating window (pickers, dialogs, popups) and
-- on the right-click menu.
vim.o.winborder = 'rounded'
vim.o.pumborder = 'rounded'

vim.o.showmode = false
-- No command line row at the bottom: it appears only while typing a `:`
-- command, and messages pop up for a few seconds in a small window instead
-- (ui2 is experimental in Neovim 0.12).
vim.o.cmdheight = 0
require('vim._core.ui2').enable({ msg = { targets = 'msg' } })

-- No `~` past the end of a buffer, no dots after a closed fold.
vim.opt.fillchars = { eob = ' ', fold = ' ' }
