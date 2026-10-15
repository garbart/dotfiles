-- Typing works right away, as in VSCode: a file in the editor is always in
-- insert mode, after opening it, clicking into its text (the cursor goes
-- where the click was, also past the end of a line) or coming back from the
-- tree, the terminal or a picker. Esc still gives Vim's normal mode, for `:q`
-- and the like; a click or switching windows brings typing back. The tree
-- and the start screen leave insert mode, so their clicks and keys work.
--
-- Text selected with the mouse or Cmd+A is replaced by what is typed (Vim's
-- Select mode; Cmd+C, Cmd+X and the like work on it, see keymaps.lua). Cmd+Z
-- undoes what was typed since the last pause, not everything since insert
-- mode began.

local M = {}

-- A text file in the editor area (not the tree, the terminal, the start
-- screen, help or a floating window).
local function is_file_win(win)
  local bo = vim.bo[vim.api.nvim_win_get_buf(win)]
  return vim.api.nvim_win_get_config(win).relative == '' and bo.buftype == '' and bo.modifiable and not bo.readonly
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
    vim.schedule(function()
      local win, mode = vim.api.nvim_get_current_win(), vim.api.nvim_get_mode().mode
      local ft = vim.bo.filetype
      if mode == 'n' and is_file_win(win) then
        vim.cmd.startinsert()
      elseif mode == 'i' and (ft == 'NvimTree' or ft == 'snacks_dashboard') then
        vim.cmd.stopinsert()
      end
    end)
  end,
})

-- A click in normal mode (after Esc, or coming from the tree) starts typing
-- at the clicked spot. In insert mode clicks need nothing.
function M.clicked()
  local pos = vim.fn.getmousepos()
  local win = vim.api.nvim_get_current_win()
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
-- The right-click menu doesn't run its items in Select mode (E335), so it
-- opens over the same selection in Visual mode.
vim.keymap.set('s', '<RightMouse>', '<C-g><RightMouse>')

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

-- Copies the selection, which stays selected, as in VSCode.
function M.copy()
  local mode = vim.fn.mode()
  local type = ({ s = 'v', S = 'V', ['\19'] = '\22' })[mode] or mode
  local text = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = type })
  vim.fn.setreg('"', text, ({ v = 'c', V = 'l', ['\22'] = 'b' })[type])
end

-- Indents (1) or outdents (-1) the selected lines by 'shiftwidth', which
-- stay selected (`>` would end the selection). Blank lines stay blank.
function M.shift(dir)
  local first, last = vim.fn.line('v'), vim.fn.line('.')
  first, last = math.min(first, last), math.max(first, last)
  local sw, ts = vim.fn.shiftwidth(), vim.bo.tabstop
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  for i, line in ipairs(lines) do
    if line:find('%S') then
      local width = math.max(vim.fn.indent(first + i - 1) + dir * sw, 0)
      local indent = vim.bo.expandtab and (' '):rep(width) or ('\t'):rep(math.floor(width / ts)) .. (' '):rep(width % ts)
      lines[i] = indent .. line:gsub('^%s*', '')
    end
  end
  vim.api.nvim_buf_set_lines(0, first - 1, last, false, lines)
end

-- Each pause in typing (see 'updatetime') ends an undo step.
vim.api.nvim_create_autocmd('CursorHoldI', {
  group = 'dotfiles.modeless',
  callback = function()
    vim.go.undolevels = vim.go.undolevels
  end,
})

return M
