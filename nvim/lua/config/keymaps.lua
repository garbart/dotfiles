-- VSCode shortcuts.
--
-- Ghostty sends Cmd+key to nvim as <D-key> (see ghostty/config.ghostty),
-- which also works over ssh. Cmd+Shift+key arrives as <D-KEY>. They work in
-- insert mode too, and the ones that aren't about the current file also in
-- a terminal window, like in VSCode. The Space versions work in any
-- terminal. A shell goes in a Ghostty split (Cmd+D or Cmd+Shift+D) rather
-- than inside nvim.

local actions = require('config.actions')
local modeless = require('config.modeless')

local map = vim.keymap.set
-- Normal, insert, visual and select (mouse selections, see modeless.lua);
-- plus terminal mode.
local nix = { 'n', 'i', 'x', 's' }
local nixt = { 'n', 'i', 'x', 's', 't' }

-- Files also save themselves (see autosave.lua). Cmd+S also formats C and
-- C++ by the project's .clang-format (see lsp.lua). Saving and undo say
-- nothing, as in VSCode.
map(nix, '<D-s>', function()
  require('config.lsp').format()
  vim.cmd('silent update')
end, { desc = 'Format and save' })

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
map(nixt, '<D-T>', actions.reopen_tab, { desc = 'Reopen closed tab' })

-- Ctrl+Tab / Ctrl+Shift+Tab go to the next / previous tab (Cmd+1..9 are
-- Ghostty's own tabs).
map(nixt, '<C-Tab>', actions.cycle_tab(1), { desc = 'Next tab' })
map(nixt, '<C-S-Tab>', actions.cycle_tab(-1), { desc = 'Previous tab' })

map(nixt, '<D-b>', actions.toggle_tree, { desc = 'Toggle file tree' })
map('n', '<leader>e', actions.toggle_tree, { desc = 'Toggle file tree' })

map('n', '<D-/>', 'gcc', { remap = true, desc = 'Toggle comment' })
map('x', '<D-/>', 'gc', { remap = true, desc = 'Toggle comment' })
map('s', '<D-/>', '<C-g>gc', { remap = true, desc = 'Toggle comment' })
map('i', '<D-/>', '<Cmd>normal gcc<CR>', { desc = 'Toggle comment' })

-- Editing shortcuts as in any Mac app. Copy and cut take the selection, or
-- the whole line when nothing is selected (like VSCode); both go to the
-- system clipboard. Cmd+V is Ghostty's paste (see editing.lua). Select all
-- selects in Select mode, so typing replaces everything.
map(nix, '<D-a>', modeless.select_all, { desc = 'Select all' })

map('n', '<D-z>', '<Cmd>silent undo<CR>', { desc = 'Undo' })
map('i', '<D-z>', '<C-o><Cmd>silent undo<CR>', { desc = 'Undo' })
map({ 'x', 's' }, '<D-z>', '<Esc><Cmd>silent undo<CR>', { desc = 'Undo' })
map('n', '<D-Z>', '<Cmd>silent redo<CR>', { desc = 'Redo' })
map('i', '<D-Z>', '<C-o><Cmd>silent redo<CR>', { desc = 'Redo' })
map({ 'x', 's' }, '<D-Z>', '<Esc><Cmd>silent redo<CR>', { desc = 'Redo' })

-- Cmd+C comes in the current keyboard layout (see ghostty/config.ghostty):
-- <D-с> in the Russian one.
for _, key in ipairs({ '<D-c>', '<D-с>' }) do
  map({ 'x', 's' }, key, modeless.copy, { desc = 'Copy' })
  map('n', key, 'yy', { desc = 'Copy line' })
  map('i', key, '<C-o>yy', { desc = 'Copy line' })
end
map('x', '<D-x>', 'd', { desc = 'Cut' })
map('s', '<D-x>', '<C-g>d', { desc = 'Cut' })
map('n', '<D-x>', 'dd', { desc = 'Cut line' })
map('i', '<D-x>', '<C-o>dd', { desc = 'Cut line' })

-- Cmd+G reverts the git changes in the selected lines, or the current line
-- (see actions.lua); Cmd+Z brings them back.
map(nix, '<D-g>', actions.revert_changes, { desc = 'Revert git changes' })

-- Shift+Tab outdents the line or the selection, Tab indents the selection
-- (which stays selected), as in VSCode. Tab in insert mode is as before.
map('n', '<S-Tab>', '<<', { desc = 'Outdent' })
map('i', '<S-Tab>', '<C-d>', { desc = 'Outdent' })
map({ 'x', 's' }, '<S-Tab>', function()
  modeless.shift(-1)
end, { desc = 'Outdent' })
map({ 'x', 's' }, '<Tab>', function()
  modeless.shift(1)
end, { desc = 'Indent' })

-- Moving around like in a Mac text field. Ghostty sends Cmd+Left/Right as
-- Ctrl+A/E and Option+Left/Right as Alt+B/F (what shells expect), so those
-- are remapped: line start (first non-blank) and end, word left and right.
-- Cmd+Backspace arrives as Ctrl+U, which already deletes to the line start
-- in insert mode. This replaces Vim's Ctrl+A (increment number) and Ctrl+E
-- (scroll a line).
map({ 'n', 'x' }, '<C-a>', '^', { desc = 'Line start' })
map('i', '<C-a>', '<C-o>^', { desc = 'Line start' })
map('n', '<C-e>', '$', { desc = 'Line end' })
map('x', '<C-e>', 'g_', { desc = 'Line end' })
map('i', '<C-e>', '<End>', { desc = 'Line end' })
map({ 'n', 'x' }, '<M-b>', 'b', { desc = 'Word left' })
map('i', '<M-b>', '<C-Left>', { desc = 'Word left' })
map({ 'n', 'x' }, '<M-f>', 'e', { desc = 'Word right' })
map('i', '<M-f>', '<C-Right>', { desc = 'Word right' })

-- Option+Delete deletes the word before the cursor, Option+Fn+Delete the
-- one after it (spaces, then a word or a run of punctuation), while typing
-- and on the command line; with a selection, both delete it. Unmapped, nvim
-- would take them for Esc and Delete.
local function word_after(text, col)
  local rest = text:sub(col + 1)
  local _, stop = vim.regex([[\v^\s*(\k+|(\k@!\S)+)]]):match_str(rest)
  return stop or #rest:match('^%s*')
end

map('i', '<M-BS>', '<C-w>', { desc = 'Delete word before' })
map('c', '<M-BS>', '<C-w>', { desc = 'Delete word before' })
map('i', '<M-Del>', function()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  if col < #line then
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col + word_after(line, col), { '' })
  elseif row < vim.api.nvim_buf_line_count(0) then
    -- At the end of the line: joins the next one, like Delete.
    vim.api.nvim_buf_set_text(0, row - 1, col, row, 0, { '' })
  end
end, { desc = 'Delete word after' })
map('c', '<M-Del>', function()
  local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  vim.fn.setcmdline(line:sub(1, pos - 1) .. line:sub(pos + word_after(line, pos - 1)), pos)
end, { desc = 'Delete word after' })
map('s', '<M-BS>', '<BS>', { desc = 'Delete selection' })
map('s', '<M-Del>', '<BS>', { desc = 'Delete selection' })

-- Cmd+Shift+V switches the Markdown view in .md files (like VSCode's
-- preview, see editing.lua) and does nothing elsewhere. Ghostty's own
-- Cmd+Shift+V pasted its last terminal selection, e.g. a whole screen.
map(nix, '<D-V>', '<Nop>')

-- Any other Cmd+key that reaches nvim does nothing, instead of typing its
-- name (like "<D-k>") into the text or the command line.
for key in ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,./;'):gmatch('.') do
  local lhs = '<D-' .. key .. '>'
  for _, mode in ipairs({ 'i', 'c', 's' }) do
    if vim.fn.maparg(lhs, mode) == '' then
      map(mode, lhs, '<Nop>')
    end
  end
end

-- `:q` by the same keys in the Russian layout: Shift+Ж (where `:` is) opens
-- the command line, and `й` (where `q` is) typed alone there is `q`, also in
-- `:й!`. Cyrillic anywhere else on the command line stays as typed.
map({ 'n', 'x' }, 'Ж', ':', { desc = 'Command line' })
map('ca', 'й', function()
  return (vim.fn.getcmdtype() == ':' and vim.fn.getcmdline() == 'й') and 'q' or 'й'
end, { expr = true })
