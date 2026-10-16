-- Right-click menus, short like VSCode's: one for code, one for the tree,
-- one for terminals (:terminal) and one for tabs. Shortcuts are shown on the
-- right of each item.

local actions = require('config.actions')
local hidden = require('config.hidden')

local M = {}

-- The code menu's edits act on the selection when there is one, else on the
-- current line. They check the mode themselves: for a selection made while
-- typing, Neovim runs a menu item's insert mode version.
local function editing(on_line, on_selection)
  return function()
    local mode = vim.api.nvim_get_mode().mode
    local keys
    if mode:find('^[sS\19]') then
      keys = '<C-g>' .. on_selection
    elseif mode:find('^[vV\22]') then
      keys = on_selection
    else
      keys = (mode:find('^i') and '<C-o>' or '') .. on_line
    end
    -- Remapped: gc and gcc are Neovim's own mappings. Ahead of anything
    -- already typed, such as the release of the click on the menu.
    vim.api.nvim_feedkeys(vim.keycode(keys), 'mi', false)
  end
end

-- Menu actions written in Lua; items call them by name.
local run = {
  palette = actions.commands,
  cut = editing('dd', 'd'),
  paste = editing('P', 'P'),
  comment = editing('gcc', 'gc'),
  copy = function()
    if vim.api.nvim_get_mode().mode:find('^[vVsS\19\22]') then
      require('config.modeless').copy()
      -- Back to Select mode, which the menu left (see modeless.lua): the
      -- selection stays, and typing replaces it.
      vim.api.nvim_feedkeys(vim.keycode('<C-g>'), 'ni', false)
    else
      vim.cmd('normal! yy')
    end
  end,
  select_all = function()
    require('config.modeless').select_all()
  end,
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
  hide = function()
    hidden.hide(M.node_path())
  end,
  unhide = function()
    hidden.unhide(M.node_path())
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

-- The tree node under the cursor (the clicked one) and its folder.
function M.node_path()
  local node = require('nvim-tree.api').tree.get_node_under_cursor()
  return node and node.absolute_path, node and node.type
end

function M.node_dir()
  local path, type = M.node_path()
  if not path then
    return nil
  end
  return type == 'directory' and path or vim.fs.dirname(path)
end

-- The same action in normal, visual, select and insert mode.
local function anywhere(name)
  local rhs = lua(name)
  return { n = rhs, x = rhs, s = rhs, i = rhs }
end

-- Item: { label, shortcut, { mode = rhs, ... } }, or '-' for a separator.
-- Modes: n, x (visual), s (select, see modeless.lua), i, t (terminal).
local menus = {
  code = {
    { 'Cut', '⌘X', anywhere('cut') },
    { 'Copy', '⌘C', anywhere('copy') },
    { 'Paste', '⌘V', anywhere('paste') },
    '-',
    { 'Select All', '⌘A', anywhere('select_all') },
    { 'Toggle Comment', '⌘/', anywhere('comment') },
    '-',
    { 'Command Palette', '⇧⌘P', anywhere('palette') },
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
    { 'Copy', '⌘C', { x = lua('copy'), s = lua('copy') } },
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

-- The tree menu, plus Hide for the clicked file, or Unhide when it is hidden
-- and shown by the eye button (see hidden.lua).
local function tree_menu()
  local path = M.node_path()
  local state = path and hidden.state(path)
  local items = vim.list_extend({}, menus.tree)
  if state == 'visible' then
    vim.list_extend(items, { '-', { 'Hide', '', { n = lua('hide') } } })
  elseif state == 'listed' then
    vim.list_extend(items, { '-', { 'Unhide', '', { n = lua('unhide') } } })
  end
  return items
end

-- Neovim's own right-click menu is about LSP and diagnostics; ours is
-- picked for whatever is under the mouse right before it opens.
pcall(vim.api.nvim_del_augroup_by_name, 'nvim.popupmenu')
vim.api.nvim_create_autocmd('MenuPopup', {
  group = vim.api.nvim_create_augroup('dotfiles.popupmenu', {}),
  callback = function()
    local ft, bt = vim.bo.filetype, vim.bo.buftype
    if ft == 'NvimTree' then
      define('PopUp', tree_menu())
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
