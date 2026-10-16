-- Editor actions shared by the shortcuts, the start screen and the explorer
-- header buttons.

local util = require('config.util')

local M = {}

-- Runs fn in the editor window, so tab actions work while the tree or a
-- bottom panel has focus.
local function in_editor(fn)
  return function()
    vim.cmd.stopinsert()
    local win = util.editor_win()
    if win then
      vim.api.nvim_set_current_win(win)
      fn()
    end
  end
end

function M.quick_open()
  vim.cmd.stopinsert()
  Snacks.picker.smart({ layout = 'vscode' })
end

function M.find_in_files()
  vim.cmd.stopinsert()
  Snacks.picker.grep()
end

function M.commands()
  vim.cmd.stopinsert()
  Snacks.picker.commands({ layout = 'vscode' })
end

function M.toggle_tree()
  vim.cmd.NvimTreeToggle()
end

-- Closes a tab (the current one by default) and keeps the window layout.
-- Changes are saved first (see autosave.lua); only a new unnamed file asks.
-- After the last tab the start screen is back.
function M.close_buffer(buf)
  require('config.autosave').save_all()
  Snacks.bufdelete(buf)
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.name ~= '' then
      return
    end
  end
  local win = util.editor_win()
  if win then
    require('config.dashboard').open(win)
  end
end

M.close_tab = in_editor(function()
  M.close_buffer()
end)

-- The files of closed tabs, the last closed at the end, with their cursor:
-- whatever closes them (Cmd+W, the tab's ×, Close Others, Close All).
local closed = {}

vim.api.nvim_create_autocmd('BufDelete', {
  group = vim.api.nvim_create_augroup('dotfiles.closed_tabs', {}),
  callback = function(args)
    local buf, path = args.buf, vim.api.nvim_buf_get_name(args.buf)
    if not vim.bo[buf].buflisted or vim.bo[buf].buftype ~= '' or vim.fn.filereadable(path) == 0 then
      return
    end
    local win = vim.fn.bufwinid(buf)
    local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or vim.api.nvim_buf_get_mark(buf, '"')
    closed = vim.tbl_filter(function(tab)
      return tab.path ~= path
    end, closed)
    table.insert(closed, { path = path, cursor = cursor })
  end,
})

-- Opens the last closed tab again, at its cursor, like VSCode's Cmd+Shift+T.
-- Files open again by now or gone from the disk are skipped.
M.reopen_tab = in_editor(function()
  while #closed > 0 do
    local tab = table.remove(closed)
    local buf = vim.fn.bufnr(tab.path)
    if vim.fn.filereadable(tab.path) == 1 and not (buf ~= -1 and vim.bo[buf].buflisted) then
      vim.cmd.edit(vim.fn.fnameescape(tab.path))
      pcall(vim.api.nvim_win_set_cursor, 0, tab.cursor)
      return
    end
  end
end)

-- Closes every tab except buf's.
function M.close_other_tabs(buf)
  local win = util.editor_win()
  if win then
    require('config.autosave').save_all()
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_call(win, function()
      Snacks.bufdelete.other()
    end)
  end
end

function M.close_all_tabs()
  require('config.autosave').save_all()
  Snacks.bufdelete.all()
  local win = util.editor_win()
  if win then
    require('config.dashboard').open(win)
  end
end

-- Goes to the next (1) or previous (-1) tab, round from the last to the
-- first.
function M.cycle_tab(dir)
  return in_editor(function()
    require('bufferline').cycle(dir)
  end)
end

-- Reverts the git changes (the bars by the line numbers) in the selected
-- lines, or in the current line, to what git has, like VSCode's Revert
-- Selected Ranges. It is an edit like any other: Cmd+Z brings them back. A
-- selection ends, back to typing.
function M.revert_changes()
  local range = { vim.fn.line('v'), vim.fn.line('.') }
  if vim.api.nvim_get_mode().mode:find('^[vVsS\22\19]') then
    vim.cmd('normal! \27')
  end
  require('gitsigns').reset_hunk(range)
end

-- The folder new files go to, like in the VSCode explorer: the open folder
-- or the file under the tree's cursor (the tree follows the current file).
-- A collapsed folder counts as not selected (the cursor rests on one when
-- the project opens), so the file goes next to it, e.g. to the root.
local function target_dir()
  local api = require('nvim-tree.api')
  local win = api.tree.winid()
  local node = win and vim.api.nvim_win_call(win, api.tree.get_node_under_cursor)
  if node and node.type == 'directory' and node.open and node.name ~= '..' then
    return node.absolute_path
  end
  if node and node.absolute_path then
    return vim.fs.dirname(node.absolute_path)
  end
  return vim.fn.getcwd()
end

local function prompt(what, dir)
  local rel = vim.fs.relpath(vim.fn.getcwd(), dir)
  return (rel and rel ~= '.') and ('%s in %s/'):format(what, rel) or what
end

-- Asks for a name (subfolders allowed) and opens the new file in the editor.
-- dir defaults to the folder selected in the tree.
function M.new_file(dir)
  dir = dir or target_dir()
  vim.ui.input({ prompt = prompt('New file', dir) }, function(name)
    if not name or vim.trim(name) == '' then
      return
    end
    local path = vim.fs.joinpath(dir, vim.trim(name))
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    if not vim.uv.fs_stat(path) then
      vim.fn.writefile({}, path)
    end
    local win = util.editor_win()
    if win then
      vim.api.nvim_set_current_win(win)
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
    require('nvim-tree.api').tree.reload()
  end)
end

function M.new_folder(dir)
  dir = dir or target_dir()
  vim.ui.input({ prompt = prompt('New folder', dir) }, function(name)
    if not name or vim.trim(name) == '' then
      return
    end
    vim.fn.mkdir(vim.fs.joinpath(dir, vim.trim(name)), 'p')
    require('nvim-tree.api').tree.reload()
  end)
end

return M
