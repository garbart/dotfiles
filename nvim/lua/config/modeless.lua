-- Typing works right away, as in VSCode: a file in the editor is always in
-- insert mode, after opening it, clicking into its text (the cursor goes
-- where the click was, also past the end of a line) or coming back from the
-- tree or a picker. Esc still gives Vim's normal mode, for `:q` and the
-- like; a click or switching windows brings typing back. The tree and the
-- start screen leave insert mode, so their clicks and keys work; their text
-- can't be selected and they show no cursor. Nor does a read-only view of
-- text (Markdown's rendered view, see markdown.lua), whose text can be
-- selected and copied.
--
-- Text selected with the mouse or Cmd+A is replaced by what is typed (Vim's
-- Select mode; Cmd+C, Cmd+X and the like work on it, see keymaps.lua). Cmd+Z
-- undoes what was typed since the last pause, not everything since insert
-- mode began.

local M = {}

-- Windows that aren't text: the tree, the start screen, an image (snacks'
-- viewer, see ui.lua) and the notice of a file too big to open right away
-- (see bigfile.lua).
local NOT_TEXT = { NvimTree = true, snacks_dashboard = true, image = true, bigfile = true }

-- No typing and no cursor there: those, and read-only views of text.
local function no_cursor(buf)
  return NOT_TEXT[vim.bo[buf].filetype] or vim.b[buf].read_only_view
end

-- A text file in the editor area (not the tree, the terminal, the start
-- screen, help or a floating window).
local function is_file_win(win)
  local bo = vim.bo[vim.api.nvim_win_get_buf(win)]
  return vim.api.nvim_win_get_config(win).relative == '' and bo.buftype == '' and bo.modifiable and not bo.readonly
end

-- A terminal (:terminal) whose program is still running: typing goes to the
-- program, as in VSCode's terminal.
local function is_live_terminal(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local channel = vim.bo[buf].channel
  return vim.bo[buf].buftype == 'terminal' and channel > 0 and vim.fn.jobwait({ channel }, 0)[1] == -1
end

vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'WinEnter' }, {
  group = vim.api.nvim_create_augroup('dotfiles.modeless', {}),
  callback = function()
    -- Not during startup, when windows are still being set up (VimEnter
    -- covers it).
    if vim.v.vim_did_enter == 0 then
      return
    end
    -- Checked once the switch is over: pickers and tab actions stop insert
    -- mode on their way.
    vim.schedule(M.settle)
  end,
})

-- A click in normal mode (after Esc, or coming from the tree) starts typing
-- at the clicked spot, or into the program of a terminal. In insert mode
-- clicks need nothing.
function M.clicked()
  local pos = vim.fn.getmousepos()
  local win = vim.api.nvim_get_current_win()
  -- On an image: zoom (see imageview.lua).
  if pos.winid == win and require('config.imageview').click(win, pos.winrow, pos.wincol) then
    return
  end
  -- On an image in Markdown's rendered view: the image file.
  if pos.winid == win and require('config.markdown').clicked(pos) then
    return
  end
  if pos.winid == win and is_live_terminal(win) then
    vim.cmd.startinsert()
    return
  end
  if pos.winid ~= win or pos.line == 0 or not is_file_win(win) then
    return
  end
  -- Past the end of the line the cursor goes after the last character.
  if pos.column > #vim.fn.getline(pos.line) then
    vim.cmd.startinsert({ bang = true })
  else
    vim.cmd.startinsert()
  end
end

vim.keymap.set('n', '<LeftMouse>', "<LeftMouse><Cmd>lua require('config.modeless').clicked()<CR>")

-- Mouse selections are in Select mode: typing replaces them.
vim.o.selectmode = 'mouse'

-- Shift+click selects from the cursor, or from the start of the selection,
-- to the clicked spot, as in VSCode (Ghostty passes it on, see
-- mouse-shift-capture in config.ghostty).
function M.shift_clicked()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= vim.api.nvim_get_current_win() or pos.line == 0 then
    return
  end
  local selecting = vim.api.nvim_get_mode().mode:find('^[vVsS\22\19]') ~= nil
  local start = vim.fn.getpos(selecting and 'v' or '.')
  local col = math.min(pos.column, math.max(#vim.fn.getline(pos.line), 1))
  -- Typing, the cursor is before a character: a selection back from it
  -- doesn't take that one.
  if not selecting and (pos.line < start[2] or pos.line == start[2] and col < start[3]) and start[3] > 1 then
    start[3] = start[3] - 1
  end
  local keys = '<C-\\><C-n><Cmd>call setpos(".", %s)<CR>v<Cmd>call cursor(%d, %d)<CR><C-g>'
  vim.api.nvim_feedkeys(vim.keycode(keys:format(vim.fn.string(start), pos.line, col)), 'n', false)
end

vim.keymap.set({ 'n', 'i', 'x', 's' }, '<S-LeftMouse>', M.shift_clicked)

-- Nothing is selected in the tree or on the start screen, as in VSCode: a
-- drag or a triple click there, or v / V, starts a selection that ends right
-- away.
vim.api.nvim_create_autocmd('ModeChanged', {
  group = 'dotfiles.modeless',
  pattern = '*:[vVsS\x16\x13]*',
  callback = function()
    if NOT_TEXT[vim.bo.filetype] then
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false)
    end
  end,
})

-- Nor do they show a cursor (the tree highlights its current line instead):
-- while one has the focus, the cursor in normal mode gets a highlight with
-- blend=100, which hides the terminal's cursor (see theme.lua). The command
-- line keeps its cursor.
local guicursor = vim.o.guicursor

local function hide_cursor()
  vim.o.guicursor = no_cursor(0) and guicursor .. ',n:HiddenCursor' or guicursor
end

-- Typing where the current window takes it, normal mode and no cursor where
-- it doesn't (also after a view is switched, see markdown.lua).
function M.settle()
  local win, mode = vim.api.nvim_get_current_win(), vim.api.nvim_get_mode().mode
  if mode == 'n' and is_file_win(win) then
    vim.cmd.startinsert()
  elseif mode == 'nt' and is_live_terminal(win) then
    vim.cmd.startinsert()
  elseif mode == 'i' and no_cursor(0) then
    vim.cmd.stopinsert()
  end
  hide_cursor()
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, { group = 'dotfiles.modeless', callback = hide_cursor })
-- They get their file type after they are entered, the start screen without
-- a FileType event (snacks sets it with events off); checked once that's
-- done and the window is the current one. An image gets it after typing
-- started there, as in any file, which then stops.
vim.api.nvim_create_autocmd('FileType', {
  group = 'dotfiles.modeless',
  pattern = { 'NvimTree', 'image', 'bigfile' },
  callback = function()
    vim.schedule(function()
      if NOT_TEXT[vim.bo.filetype] and vim.api.nvim_get_mode().mode == 'i' then
        vim.cmd.stopinsert()
      end
      hide_cursor()
    end)
  end,
})
vim.api.nvim_create_autocmd('User', {
  group = 'dotfiles.modeless',
  pattern = 'SnacksDashboardOpened',
  callback = function()
    vim.schedule(hide_cursor)
  end,
})

-- Leaving a selection (Esc, copy, cut, comment) goes back to typing rather
-- than to normal mode.
vim.api.nvim_create_autocmd('ModeChanged', {
  group = 'dotfiles.modeless',
  pattern = '[vVsS\x16\x13]*:n',
  callback = function()
    vim.schedule(function()
      if vim.api.nvim_get_mode().mode == 'n' and is_file_win(vim.api.nvim_get_current_win()) then
        vim.cmd.startinsert()
      end
    end)
  end,
})

-- Selection commands for keymaps.lua and the right-click menu. They work
-- through the API rather than keys: a selection made while typing returns to
-- insert mode after a command, and any key after it would be typed in.

-- Select all, in Select mode.
function M.select_all()
  vim.api.nvim_feedkeys(vim.keycode('<C-\\><C-n>ggVG<C-g>'), 'n', false)
end

-- Copies the selection, which stays selected, as in VSCode: to the system
-- clipboard (+, see 'clipboard' in options.lua; setting " alone doesn't
-- reach it) and to the unnamed register, as a yank does.
function M.copy()
  local mode = vim.fn.mode()
  local type = ({ s = 'v', S = 'V', ['\19'] = '\22' })[mode] or mode
  local text = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = type })
  local regtype = ({ v = 'c', V = 'l', ['\22'] = 'b' })[type]
  vim.fn.setreg('+', text, regtype)
  vim.fn.setreg('"', text, regtype)
end

-- Indents (1) or outdents (-1) the selected lines by 'shiftwidth', which
-- stay selected (`>` would end the selection). Blank lines stay blank. Only
-- the leading whitespace is replaced: rewriting whole lines would drop the
-- breakpoints and git marks on them.
function M.shift(dir)
  local first, last = vim.fn.line('v'), vim.fn.line('.')
  first, last = math.min(first, last), math.max(first, last)
  local sw, ts = vim.fn.shiftwidth(), vim.bo.tabstop
  for lnum = first, last do
    local line = vim.fn.getline(lnum)
    if line:find('%S') then
      local width = math.max(vim.fn.indent(lnum) + dir * sw, 0)
      local indent = vim.bo.expandtab and (' '):rep(width) or ('\t'):rep(math.floor(width / ts)) .. (' '):rep(width % ts)
      vim.api.nvim_buf_set_text(0, lnum - 1, 0, lnum - 1, #line:match('^%s*'), { indent })
    end
  end
end

-- Each pause in typing (see 'updatetime') ends an undo step.
vim.api.nvim_create_autocmd('CursorHoldI', {
  group = 'dotfiles.modeless',
  callback = function()
    vim.go.undolevels = vim.go.undolevels
  end,
})

return M
