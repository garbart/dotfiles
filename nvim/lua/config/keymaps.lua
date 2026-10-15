-- VSCode shortcuts.
--
-- Ghostty sends Cmd+key to nvim as <D-key> (see ghostty/config.ghostty),
-- which also works over ssh. Cmd+Shift+key arrives as <D-KEY>. They work in
-- insert mode too, and the ones that aren't about the current file also in
-- the terminal panel, like in VSCode. The Space versions work in any
-- terminal.

local actions = require('config.actions')

local map = vim.keymap.set
local nix = { 'n', 'i', 'x' }
local nixt = { 'n', 'i', 'x', 't' }

map(nix, '<D-s>', '<Cmd>write<CR>', { desc = 'Save' })

map(nixt, '<D-p>', actions.quick_open, { desc = 'Quick open' })
map('n', '<leader><leader>', actions.quick_open, { desc = 'Quick open' })

map(nixt, '<D-P>', actions.commands, { desc = 'Command palette' })
map('n', '<leader>p', actions.commands, { desc = 'Command palette' })

map(nixt, '<D-F>', actions.find_in_files, { desc = 'Find in files' })
map('n', '<leader>/', actions.find_in_files, { desc = 'Find in files' })

map('n', '<D-f>', '/', { desc = 'Find in file' })
map('i', '<D-f>', '<Esc>/', { desc = 'Find in file' })

map(nix, '<D-w>', actions.close_tab, { desc = 'Close tab' })
map('n', '<leader>w', actions.close_tab, { desc = 'Close tab' })

-- Cmd+1..8 open the tab with that number, Cmd+9 the last one.
for i = 1, 9 do
  map(nixt, ('<D-%d>'):format(i), actions.goto_tab(i == 9 and -1 or i), {
    desc = i == 9 and 'Last tab' or ('Tab ' .. i),
  })
end

map(nixt, '<D-b>', actions.toggle_tree, { desc = 'Toggle file tree' })
map('n', '<leader>e', actions.toggle_tree, { desc = 'Toggle file tree' })

map('n', '<D-/>', 'gcc', { remap = true, desc = 'Toggle comment' })
map('x', '<D-/>', 'gc', { remap = true, desc = 'Toggle comment' })
map('i', '<D-/>', '<Cmd>normal gcc<CR>', { desc = 'Toggle comment' })

map({ 'n', 'i', 't' }, '<C-`>', actions.toggle_terminal, { desc = 'Toggle terminal' })
map('n', '<leader>t', actions.toggle_terminal, { desc = 'Toggle terminal' })

-- Editing shortcuts as in any Mac app. Copy and cut take the selection, or
-- the whole line when nothing is selected (like VSCode); both go to the
-- system clipboard. Cmd+V is Ghostty's paste (see editing.lua).
map('n', '<D-a>', 'ggVG', { desc = 'Select all' })
map({ 'i', 'x' }, '<D-a>', '<Esc>ggVG', { desc = 'Select all' })

map('n', '<D-z>', 'u', { desc = 'Undo' })
map('i', '<D-z>', '<C-o>u', { desc = 'Undo' })
map('x', '<D-z>', '<Esc>u', { desc = 'Undo' })
map('n', '<D-Z>', '<C-r>', { desc = 'Redo' })
map('i', '<D-Z>', '<C-o><C-r>', { desc = 'Redo' })
map('x', '<D-Z>', '<Esc><C-r>', { desc = 'Redo' })

map('x', '<D-c>', 'y', { desc = 'Copy' })
map('n', '<D-c>', 'yy', { desc = 'Copy line' })
map('i', '<D-c>', '<C-o>yy', { desc = 'Copy line' })
map('x', '<D-x>', 'd', { desc = 'Cut' })
map('n', '<D-x>', 'dd', { desc = 'Cut line' })
map('i', '<D-x>', '<C-o>dd', { desc = 'Cut line' })

-- Moving around like in a Mac text field. Ghostty sends Cmd+Left/Right as
-- Ctrl+A/E and Option+Left/Right as Alt+B/F (what shells expect), so those
-- are remapped: line start (first non-blank) and end, word left and right.
-- Cmd+Backspace arrives as Ctrl+U, which already deletes to the line start
-- in insert mode; Option+Backspace deletes the word before the cursor.
-- This replaces Vim's Ctrl+A (increment number) and Ctrl+E (scroll a line).
map({ 'n', 'x' }, '<C-a>', '^', { desc = 'Line start' })
map('i', '<C-a>', '<C-o>^', { desc = 'Line start' })
map('n', '<C-e>', '$', { desc = 'Line end' })
map('x', '<C-e>', 'g_', { desc = 'Line end' })
map('i', '<C-e>', '<End>', { desc = 'Line end' })
map({ 'n', 'x' }, '<M-b>', 'b', { desc = 'Word left' })
map('i', '<M-b>', '<C-Left>', { desc = 'Word left' })
map({ 'n', 'x' }, '<M-f>', 'e', { desc = 'Word right' })
map('i', '<M-f>', '<C-Right>', { desc = 'Word right' })
map('i', '<M-BS>', '<C-w>', { desc = 'Delete word' })

-- Cmd+Shift+V switches the Markdown view in .md files (like VSCode's
-- preview, see editing.lua) and does nothing elsewhere. Ghostty's own
-- Cmd+Shift+V pasted its last terminal selection, e.g. a whole screen.
map(nix, '<D-V>', '<Nop>')

-- Any other Cmd+key that reaches nvim does nothing, instead of typing its
-- name (like "<D-k>") into the text or the command line.
for key in ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,./;'):gmatch('.') do
  local lhs = '<D-' .. key .. '>'
  for _, mode in ipairs({ 'i', 'c' }) do
    if vim.fn.maparg(lhs, mode) == '' then
      map(mode, lhs, '<Nop>')
    end
  end
end
