-- Editor actions shared by the shortcuts, the start screen and the explorer
-- header buttons.

local util = require('config.util')

local M = {}

-- Runs fn in the editor window, so tab actions work while the tree or the
-- terminal panel has focus.
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

function M.toggle_terminal()
  Snacks.terminal.toggle()
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

-- Opens tab n (-1 for the last one).
function M.goto_tab(n)
  return in_editor(function()
    require('bufferline').go_to(n, true)
  end)
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
