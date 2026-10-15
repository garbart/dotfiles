-- Right-click menus, short like VSCode's: one for code, one for the tree,
-- one for the terminal panel and one for tabs. Shortcuts are shown on the
-- right of each item.

local actions = require('config.actions')

local M = {}

-- Menu actions written in Lua; items call them by name.
local run = {
  palette = actions.commands,
  new_file = function()
    actions.new_file(M.node_dir())
  end,
  new_folder = function()
    actions.new_folder(M.node_dir())
  end,
  rename = function()
    require('nvim-tree.api').fs.rename()
  end,
  delete = function()
    require('nvim-tree.api').fs.remove()
  end,
  copy_path = function()
    require('nvim-tree.api').fs.copy.absolute_path()
  end,
  copy_relative_path = function()
    require('nvim-tree.api').fs.copy.relative_path()
  end,
  close_tab = function()
    actions.close_buffer(M.tab)
  end,
  close_other_tabs = function()
    actions.close_other_tabs(M.tab)
  end,
  close_all_tabs = actions.close_all_tabs,
}

function M.run(name)
  run[name]()
end

local function lua(name)
  return ("<Cmd>lua require('config.menu').run('%s')<CR>"):format(name)
end

-- The folder of the tree node under the cursor (the clicked one).
function M.node_dir()
  local node = require('nvim-tree.api').tree.get_node_under_cursor()
  if not node or not node.absolute_path then
    return nil
  end
  return node.type == 'directory' and node.absolute_path or vim.fs.dirname(node.absolute_path)
end

-- Item: { label, shortcut, { mode = rhs, ... } }, or '-' for a separator.
-- Modes: n, v (visual), i, t (terminal).
local menus = {
  code = {
    { 'Cut', '⌘X', { n = 'dd', v = 'd', i = '<C-o>dd' } },
    { 'Copy', '⌘C', { n = 'yy', v = 'y', i = '<C-o>yy' } },
    { 'Paste', '⌘V', { n = 'P', v = 'P', i = '<C-r><C-o>+' } },
    '-',
    { 'Select All', '⌘A', { n = 'ggVG', v = '<Esc>ggVG', i = '<Esc>ggVG' } },
    { 'Toggle Comment', '⌘/', { n = 'gcc', v = 'gc', i = '<Cmd>normal gcc<CR>' } },
    '-',
    { 'Command Palette', '⇧⌘P', { n = lua('palette'), v = lua('palette'), i = lua('palette') } },
  },
  tree = {
    { 'New File…', '', { n = lua('new_file') } },
    { 'New Folder…', '', { n = lua('new_folder') } },
    '-',
    { 'Rename…', '', { n = lua('rename') } },
    { 'Delete', '', { n = lua('delete') } },
    '-',
    { 'Copy Path', '', { n = lua('copy_path') } },
    { 'Copy Relative Path', '', { n = lua('copy_relative_path') } },
  },
  terminal = {
    { 'Copy', '⌘C', { v = 'y' } },
    { 'Paste', '⌘V', { n = 'p', t = '<C-\\><C-n>pi' } },
  },
  start = {
    { 'Command Palette', '⇧⌘P', { n = lua('palette') } },
  },
  tab = {
    { 'Close', '⌘W', { n = lua('close_tab') } },
    { 'Close Others', '', { n = lua('close_other_tabs') } },
    { 'Close All', '', { n = lua('close_all_tabs') } },
  },
}

local function width(text)
  return vim.fn.strdisplaywidth(text)
end

-- (Re)defines menu `name` from items, with the shortcuts right-aligned.
local function define(name, items)
  vim.cmd(('silent! aunmenu %s'):format(name))
  local w = 0
  for _, item in ipairs(items) do
    if item ~= '-' then
      w = math.max(w, width(item[1]) + width(item[2]) + 4)
    end
  end
  for i, item in ipairs(items) do
    if item == '-' then
      vim.cmd(('anoremenu %s.-%d- <Nop>'):format(name, i))
    else
      local text = item[1] .. (' '):rep(w - width(item[1]) - width(item[2])) .. item[2]
      local path = name .. '.' .. text:gsub('[%s%.\\]', '\\%0'):gsub('&', '&&')
      for mode, rhs in pairs(item[3]) do
        local cmd = mode == 't' and 'tlnoremenu' or (mode .. 'noremenu')
        vim.cmd(('%s %s %s'):format(cmd, path, rhs))
      end
    end
  end
end

-- Neovim's own right-click menu is about LSP and diagnostics; ours is
-- picked for whatever is under the mouse right before it opens.
pcall(vim.api.nvim_del_augroup_by_name, 'nvim.popupmenu')
vim.api.nvim_create_autocmd('MenuPopup', {
  group = vim.api.nvim_create_augroup('dotfiles.popupmenu', {}),
  callback = function()
    local ft, bt = vim.bo.filetype, vim.bo.buftype
    if ft == 'NvimTree' then
      define('PopUp', menus.tree)
    elseif bt == 'terminal' then
      define('PopUp', menus.terminal)
    elseif ft == 'snacks_dashboard' then
      define('PopUp', menus.start)
    else
      define('PopUp', menus.code)
    end
  end,
})

-- Tabs (bufferline's right click): the menu for the clicked tab.
function M.tab_menu(buf)
  M.tab = buf
  define('TabMenu', menus.tab)
  vim.cmd('popup! TabMenu')
end

return M
