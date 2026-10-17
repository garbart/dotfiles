-- Right-click menus, short like VSCode's: one for code, one for the tree,
-- one for terminals (:terminal) and one for the start screen. Each item has
-- a key on the right, as in Claude's menus: typed while the menu is open
-- (in the Russian layout too), it runs the item. Where an item has a Cmd
-- shortcut, its key is that one's letter (X as in Cmd+X). The mouse picks
-- items as in any menu; the arrows and Enter too, Esc closes it.
--
-- The code menu has what applies where it was opened: the language
-- server's go to definition, find all references and rename (see lsp.lua),
-- reverting the git changes of the line or selection, and a link to it on
-- the git host (see gitlink.lua); no edits in a read-only view.
--
-- The menu is a floating window of its own (Neovim's menus take no such
-- keys) that doesn't take the focus, so a selection stays selected for the
-- items.

local actions = require('config.actions')
local hidden = require('config.hidden')

local M = {}

local SELECTION = '^[vVsS\22\19]'

-- The code menu's edits act on the selection when there is one, else on the
-- current line.
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
    -- already typed.
    vim.api.nvim_feedkeys(vim.keycode(keys), 'mi', false)
  end
end

local function copy()
  if vim.api.nvim_get_mode().mode:find(SELECTION) then
    require('config.modeless').copy()
  else
    vim.cmd('normal! yy')
  end
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

-- The selected lines, or the cursor's.
local function lines()
  local first, last = vim.fn.line('v'), vim.fn.line('.')
  if not vim.api.nvim_get_mode().mode:find(SELECTION) then
    first = last
  end
  return math.min(first, last), math.max(first, last)
end

-- Whether git sees changes in those lines (the bars by the line numbers).
local function git_changes()
  local ok, hunks = pcall(require('gitsigns').get_hunks)
  local first, last = lines()
  for _, hunk in ipairs(ok and hunks or {}) do
    -- (A deletion is marked on the line before it.)
    local start = math.max(hunk.added.start, 1)
    local stop = start + math.max(hunk.added.count, 1) - 1
    if start <= last and stop >= first then
      return true
    end
  end
  return false
end

-- A menu: a list of { label, key, action }, with '-' between groups; and
-- functions to add an item and to start a group.
local function menu()
  local items = {}
  return items,
    function(label, key, action)
      table.insert(items, { label, key, action })
    end,
    function()
      if #items > 0 and items[#items] ~= '-' then
        table.insert(items, '-')
      end
    end
end

local function code_menu()
  local lsp, gitlink = require('config.lsp'), require('config.gitlink')
  local editable = vim.bo.modifiable
  local items, add, group = menu()
  if lsp.can('textDocument/definition') then
    add('Go to Definition', 'd', lsp.definition)
  end
  if lsp.can('textDocument/references') then
    add('Find All References', 'r', lsp.references)
  end
  if editable and lsp.can('textDocument/rename') then
    add('Rename Symbol…', 'n', lsp.rename)
  end
  group()
  if editable then
    add('Cut', 'x', editing('dd', 'd'))
  end
  add('Copy', 'c', copy)
  if editable then
    add('Paste', 'v', editing('P', 'P'))
  end
  group()
  if editable and git_changes() then
    add('Revert Git Changes', 'g', actions.revert_changes)
  end
  if gitlink.available() then
    add('Copy Git Link', 'l', gitlink.copy)
  end
  group()
  add('Select All', 'a', require('config.modeless').select_all)
  if editable then
    add('Toggle Comment', '/', editing('gcc', 'gc'))
  end
  group()
  add('Command Palette', 'p', actions.commands)
  return items
end

-- The tree's, plus Hide for the selected files that are shown, and Unhide
-- for those hidden and shown by the eye button (see hidden.lua).
local function tree_menu()
  local api = require('nvim-tree.api')
  local items, add, group = menu()
  add('New File…', 'n', function()
    actions.new_file(M.node_dir())
  end)
  add('New Folder…', 'f', function()
    actions.new_folder(M.node_dir())
  end)
  group()
  add('Rename…', 'r', api.fs.rename)
  add('Delete', 'd', function()
    require('config.tree').delete()
  end)
  group()
  add('Copy Path', 'p', function()
    require('config.tree').copy_paths(true)
  end)
  add('Copy Relative Path', 'c', function()
    require('config.tree').copy_paths(false)
  end)
  local by_state = { visible = {}, listed = {} }
  for _, path in ipairs(require('config.tree').targets()) do
    local list = by_state[hidden.state(path) or '']
    if list then
      table.insert(list, path)
    end
  end
  group()
  if #by_state.visible > 0 then
    add('Hide', 'h', function()
      require('config.tree').clear_selection()
      hidden.hide(by_state.visible)
    end)
  end
  if #by_state.listed > 0 then
    add('Unhide', 'u', function()
      require('config.tree').clear_selection()
      hidden.unhide(by_state.listed)
    end)
  end
  return items
end

local function terminal_menu()
  local items, add = menu()
  if vim.api.nvim_get_mode().mode:find(SELECTION) then
    add('Copy', 'c', copy)
  end
  add('Paste', 'v', function()
    local keys = vim.api.nvim_get_mode().mode == 't' and '<C-\\><C-n>pi' or 'p'
    vim.api.nvim_feedkeys(vim.keycode(keys), 'n', false)
  end)
  return items
end

local function start_menu()
  local items, add = menu()
  add('Command Palette', 'p', actions.commands)
  return items
end

Snacks.util.set_hl({ DotfilesMenuKey = 'Comment' }, { default = true })

-- Shows a menu just below and right of a screen cell (1-based), or where
-- it fits, and returns the item picked, if any.
local function choose(items, row, col)
  if items[#items] == '-' then
    table.remove(items)
  end
  local widest = 0
  for _, item in ipairs(items) do
    widest = item ~= '-' and math.max(widest, vim.fn.strdisplaywidth(item[1])) or widest
  end
  local width = widest + 6
  local text = {}
  for _, item in ipairs(items) do
    if item == '-' then
      table.insert(text, ('─'):rep(width))
    else
      local pad = (' '):rep(width - 3 - vim.fn.strdisplaywidth(item[1]))
      table.insert(text, ' ' .. item[1] .. pad .. item[2]:upper() .. ' ')
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  local ns = vim.api.nvim_create_namespace('dotfiles.menu')
  for i, item in ipairs(items) do
    local from, to, hl = #text[i] - 2, #text[i] - 1, 'DotfilesMenuKey'
    if item == '-' then
      from, to, hl = 0, #text[i], 'FloatBorder'
    end
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, from, { end_col = to, hl_group = hl })
  end
  local height = #text
  local top = row + height + 2 > vim.o.lines - 1 and math.max(0, row - height - 3) or row
  local left = math.max(0, math.min(col - 1, vim.o.columns - width - 2))
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = top,
    col = left,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    zindex = 250,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel'

  local selected
  local function select(i)
    selected = i and items[i] and items[i] ~= '-' and i or nil
    vim.wo[win].cursorline = selected ~= nil
    if selected then
      vim.api.nvim_win_set_cursor(win, { selected, 0 })
    end
  end
  local function step(dir)
    local i = selected or (dir > 0 and 0 or #items + 1)
    repeat
      i = (i + dir - 1) % #items + 1
    until items[i] ~= '-'
    select(i)
  end
  -- The menu's line under the mouse, and whether the mouse is on the menu.
  local function under_mouse()
    local pos = vim.fn.getmousepos()
    return pos.winid == win and pos.line or nil, pos.winid == win
  end
  local by_key = {}
  for i, item in ipairs(items) do
    if item ~= '-' then
      by_key[item[2]] = i
    end
  end

  -- The item under the mouse is highlighted as it moves: reading keys
  -- skips mouse moves, so its position is checked a few times a second
  -- (the terminal sends it with 'mousemoveevent' on).
  local mousemoveevent = vim.o.mousemoveevent
  vim.o.mousemoveevent = true
  local hover, open, last = assert(vim.uv.new_timer()), true, nil
  hover:start(30, 30, vim.schedule_wrap(function()
    local pos = vim.fn.getmousepos()
    local at = pos.screenrow .. ':' .. pos.screencol
    if open and at ~= last then
      last = at
      select(under_mouse())
      vim.cmd.redraw()
    end
  end))

  -- Keys and mouse clicks are read here until an item is picked or the menu
  -- closes. A click counts on its release, which so doesn't reach what is
  -- under the menu.
  local picked, pressed, outside
  while true do
    vim.cmd.redraw()
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok then
      break
    end
    local key = vim.fn.keytrans(char)
    -- A letter in the Russian layout, or with Cmd (the item's shortcut).
    local letter = key:match('^<D%-(.)>$') or vim.fn.strcharlen(char) == 1 and require('config.layout').latin(char)
    if key == '<LeftDrag>' then
      select(under_mouse())
    elseif key == '<LeftMouse>' then
      local line, inside = under_mouse()
      pressed, outside = line, not inside
    elseif key == '<LeftRelease>' then
      if outside then
        break
      end
      if pressed and pressed == under_mouse() and items[pressed] ~= '-' then
        picked = pressed
        break
      end
    elseif key == '<RightMouse>' then
      -- (Off the menu it closes it.)
      local _, inside = under_mouse()
      if not inside then
        break
      end
    elseif key == '<Esc>' or key == '<C-C>' then
      break
    elseif key == '<Down>' or key == '<Tab>' or key == '<C-N>' then
      step(1)
    elseif key == '<Up>' or key == '<S-Tab>' or key == '<C-P>' then
      step(-1)
    elseif key == '<CR>' then
      if selected then
        picked = selected
        break
      end
    elseif letter and by_key[letter:lower()] then
      picked = by_key[letter:lower()]
      break
    end
  end
  open = false
  hover:close()
  vim.o.mousemoveevent = mousemoveevent
  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return picked and items[picked]
end

-- Whether a buffer position (1-based line, 0-based column) is in the
-- selection.
local function in_selection(line, col)
  local a, b = vim.fn.getpos('v'), vim.fn.getpos('.')
  if a[2] > b[2] or a[2] == b[2] and a[3] > b[3] then
    a, b = b, a
  end
  if line < a[2] or line > b[2] then
    return false
  end
  local linewise = vim.api.nvim_get_mode().mode:find('^[VS]') ~= nil
  return linewise or (line > a[2] or col + 1 >= a[3]) and (line < b[2] or col + 1 <= b[3])
end

-- Right click: the menu for what is under the mouse. As with Neovim's own
-- menu, the click moves the cursor there, unless it is on the selection.
function M.open()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 or vim.api.nvim_win_get_config(pos.winid).relative ~= '' then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  local current = vim.api.nvim_get_current_win()
  local col = math.max(pos.column - 1, 0)
  if not (pos.winid == current and mode:find(SELECTION) and in_selection(pos.line, col)) then
    if mode:find(SELECTION) then
      vim.cmd('normal! \27')
    end
    if pos.winid ~= current then
      vim.api.nvim_set_current_win(pos.winid)
    end
    if mode ~= 't' then
      vim.api.nvim_win_set_cursor(pos.winid, { pos.line, col })
    end
  end

  local ft, bt = vim.bo.filetype, vim.bo.buftype
  local items
  if ft == 'NvimTree' then
    require('config.tree').right_click()
    items = tree_menu()
  elseif bt == 'terminal' then
    items = terminal_menu()
  elseif ft == 'snacks_dashboard' then
    items = start_menu()
  elseif ft ~= 'image' and ft ~= 'bigfile' then
    items = code_menu()
  end
  local item = items and #items > 0 and choose(items, pos.screenrow, pos.screencol)
  if item then
    item[3]()
  end
end

-- Right click opens ours (Neovim's own menu stays off: elsewhere, as on the
-- command line, the click does what it does without one).
vim.o.mousemodel = 'extend'
vim.keymap.set({ 'n', 'i', 'x', 's', 't' }, '<RightMouse>', M.open, { desc = 'Context menu' })

return M
