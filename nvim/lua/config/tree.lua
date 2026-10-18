-- File tree on the left, opened for `nvim` and `nvim <dir>`, with a header
-- like the VSCode explorer: project name and action buttons, in the row of
-- the tabs, above the tree.

local actions = require('config.actions')
local hidden = require('config.hidden')
local util = require('config.util')

local M = {}

-- Files hidden with right click > Hide are dimmed while the eye button
-- shows them.
local Dimmed = require('nvim-tree.api').Decorator:extend()

function Dimmed:new()
  self.enabled = true
  self.highlight_range = 'name'
  self.icon_placement = 'none'
end

function Dimmed:highlight_group(node)
  if hidden.showing and hidden.is_hidden(node.absolute_path) then
    return 'ExplorerMuted'
  end
end

-- A single click on a folder's chevron opens or closes it, as in VSCode (a
-- double click on the name works too, as before).
local arrows = { closed = '\u{f460}', open = '\u{f47c}' }

local function click_arrow()
  local api = require('nvim-tree.api')
  local pos = vim.fn.getmousepos()
  if pos.winid ~= api.tree.winid() or pos.line == 0 then
    return
  end
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(pos.winid), pos.line - 1, pos.line, false)[1]
  for _, arrow in pairs(arrows) do
    local start = line:find(arrow, 1, true)
    -- The chevron and the space after it.
    if start and pos.column >= start and pos.column <= start + #arrow then
      api.node.open.edit()
      return
    end
  end
end

require('nvim-tree').setup({
  on_attach = function(buf)
    local api = require('nvim-tree.api')
    api.config.mappings.default_on_attach(buf)
    vim.keymap.set('n', '<LeftRelease>', function()
      M.release(click_arrow)
    end, { buffer = buf, desc = 'Open/close folder, or drop' })
    vim.keymap.set('n', '<LeftDrag>', function()
      M.drag()
    end, { buffer = buf, desc = 'Move a file or folder' })
    -- Cmd+C copies the path of what is under the cursor, from the project's
    -- folder; Cmd+Shift+C the full path. Cmd+Backspace moves it to the Trash.
    -- Cmd+Z / Cmd+Shift+Z undo and redo pastes, moves and deletes. (In the
    -- Russian layout too, see layout.lua.)
    vim.keymap.set('n', '<D-c>', function()
      M.copy_paths(false)
    end, { buffer = buf, desc = 'Copy relative path' })
    vim.keymap.set('n', '<D-C>', function()
      M.copy_paths(true)
    end, { buffer = buf, desc = 'Copy path' })
    -- Selecting several (see M.click).
    vim.keymap.set('n', '<LeftMouse>', "<LeftMouse><Cmd>lua require('config.tree').click()<CR>", { buffer = buf })
    vim.keymap.set('n', '<C-LeftMouse>', function()
      M.ctrl_click()
    end, { buffer = buf, desc = 'Add to / take from the selection' })
    vim.keymap.set('n', '<S-LeftMouse>', function()
      M.shift_click()
    end, { buffer = buf, desc = 'Select up to here' })
    vim.keymap.set('n', '<Esc>', function()
      M.clear_selection()
    end, { buffer = buf, desc = 'Clear the selection' })
    -- (So do the tree's own d and D, which deleted for good or didn't work.)
    for _, key in ipairs({ '<C-u>', 'd', 'D' }) do
      vim.keymap.set('n', key, function()
        M.delete()
      end, { buffer = buf, desc = 'Move to the Trash (Cmd+Backspace)' })
    end
    vim.keymap.set('n', '<D-z>', function()
      M.undo()
    end, { buffer = buf, desc = 'Undo paste, move or delete' })
    vim.keymap.set('n', '<D-Z>', function()
      M.redo()
    end, { buffer = buf, desc = 'Redo paste, move or delete' })
    require('config.layout').twin(buf)
  end,
  -- Directories are opened by the VimEnter handler below. The built-in hijack
  -- would turn the whole window into the tree, leaving no editor on the right.
  hijack_directories = { enable = false },
  -- The cursor stays at the start of the name, so it never pulls the tree
  -- sideways.
  hijack_cursor = true,
  -- Highlight the current file in the tree, expanding folders up to it.
  update_focused_file = { enable = true },
  -- .git, and the files hidden with right click > Hide unless the eye button
  -- in the header shows them (see hidden.lua). Files git ignores (build
  -- folders and such) are shown like any other (see theme.lua); Hide hides
  -- them too.
  filters = {
    git_ignored = false,
    custom = function(path)
      return vim.fs.basename(path) == '.git' or (not hidden.showing and hidden.is_hidden(path))
    end,
  },
  -- Files open in the editor window, also while it shows the start screen
  -- (by default nvim-tree skips such windows and splits a new one).
  actions = {
    open_file = {
      window_picker = { exclude = { filetype = { 'qf', 'diff' }, buftype = { 'terminal', 'help', 'quickfix' } } },
    },
  },
  -- Laid out like the VSCode explorer: chevrons without folder icons, indent
  -- guides, file names colored by git status and the status letter on the
  -- right edge. The project name is in the header (see M.header).
  renderer = {
    root_folder_label = false,
    highlight_git = 'name',
    -- README.md and friends are not underlined in pink.
    special_files = {},
    indent_markers = { enable = true },
    decorators = { 'Git', 'Open', 'Hidden', 'Modified', 'Bookmark', 'Diagnostics', 'Copied', Dimmed, 'Cut' },
    icons = {
      git_placement = 'right_align',
      show = { folder = false },
      glyphs = {
        folder = { arrow_closed = arrows.closed, arrow_open = arrows.open },
        git = {
          unstaged = 'M',
          staged = 'M',
          unmerged = '!',
          renamed = 'R',
          untracked = 'U',
          deleted = 'D',
          ignored = '',
        },
      },
    },
  },
})

local api = require('nvim-tree.api')

-- Header buttons, as in VSCode: new file, new folder, collapse all. No
-- refresh: nvim-tree watches the file system and updates by itself (`R` in
-- the tree still reloads it by hand). Plus an eye when the project has
-- hidden files: open to show them, crossed out to hide them again.
local buttons = {
  { icon = '\u{ea7f}', run = actions.new_file },
  { icon = '\u{ea80}', run = actions.new_folder },
  {
    icon = function()
      if hidden.count() > 0 then
        return hidden.showing and '\u{eae7}' or '\u{ea70}'
      end
    end,
    run = hidden.toggle,
  },
  { icon = '\u{eac5}', run = api.tree.collapse_all },
}

-- text cut to width display cells, ending with "…" when it was cut.
local function cut(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local kept = ''
  for _, char in ipairs(vim.fn.split(text, '\\zs')) do
    if vim.fn.strdisplaywidth(kept .. char) > width - 1 then
      break
    end
    kept = kept .. char
  end
  return width > 0 and kept .. '…' or ''
end

-- The header, width cells wide: project name, `[SSH: host]` when remote,
-- buttons on the right. A name too long for the tree is cut on the right,
-- the buttons stay.
function M.header(width)
  local name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local host = vim.env.SSH_CONNECTION and vim.uv.os_gethostname():match('^[^.]*')
  local remote = host and (' [SSH: %s]'):format(host) or ''

  local items, icons = {}, {}
  for i, button in ipairs(buttons) do
    local icon = button.icon
    if type(icon) == 'function' then
      icon = icon()
    end
    if icon then
      table.insert(icons, icon)
      table.insert(items, ("%%%d@v:lua.require'config.tree'.on_click@%s%%T"):format(i, icon))
    end
  end

  -- Room left of the buttons, with a space at each edge and one before them.
  local icons_width = vim.fn.strdisplaywidth(table.concat(icons, '  '))
  local room = width - icons_width - 3
  name = cut(name, room)
  remote = cut(remote, room - vim.fn.strdisplaywidth(name))
  local gap = width - 2 - icons_width - vim.fn.strdisplaywidth(name .. remote)
  return ('%%#ExplorerTitle# %s%%#ExplorerMuted#%s%s%s '):format(
    util.escape(name),
    util.escape(remote),
    (' '):rep(gap),
    table.concat(items, '  ')
  )
end

-- The tab bar (bufferline's) with the header in the room it leaves above
-- the tree, which holds this character (see ui.lua).
M.HEADER = '\u{F8FF}'

function M.tabline()
  local line = _G.nvim_bufferline()
  local win = api.tree.winid()
  if not win then
    return line
  end
  return (line:gsub(' ' .. M.HEADER .. ' *', function()
    return M.header(vim.api.nvim_win_get_width(win))
  end, 1))
end

vim.o.tabline = "%!v:lua.require'config.tree'.tabline()"

function M.on_click(i, _, button)
  if button == 'l' then
    buttons[i].run()
  end
end

-- Names too long for the tree are cut with "…", since it does not scroll
-- sideways (see scroll.lua): the end of the line is concealed and "…" drawn
-- in its place, keeping the git letter on the right edge in view.
local cut_ns = vim.api.nvim_create_namespace('explorer.cut')
local names_ns = vim.api.nvim_create_namespace('NvimTreeHighlights')
local letters_ns = vim.api.nvim_create_namespace('NvimTreeExtmarks')

local function cut_long_names()
  local win = api.tree.winid()
  if not win then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_buf_clear_namespace(buf, cut_ns, 0, -1)
  local info = vim.fn.getwininfo(win)[1]
  local width = info.width - info.textoff

  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    row = row - 1
    local room = width
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, letters_ns, { row, 0 }, { row, -1 }, { details = true })) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        room = room - vim.fn.strdisplaywidth(chunk[1]) - 1
      end
    end

    if vim.fn.strdisplaywidth(line) > room then
      -- What fits, leaving a column for "…".
      local col, used = 0, 0
      for _, char in ipairs(vim.fn.split(line, '\\zs')) do
        used = used + vim.fn.strdisplaywidth(char)
        if used > room - 1 then
          break
        end
        col = col + #char
      end
      -- "…" in the colors of the name it ends.
      local hl = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, names_ns, { row, 0 }, { row, -1 }, { details = true })) do
        if mark[3] <= col and (mark[4].end_col or 0) > col then
          table.insert(hl, mark[4].hl_group)
        end
      end
      vim.api.nvim_buf_set_extmark(buf, cut_ns, row, col, {
        end_col = #line,
        conceal = '',
        virt_text = { { '…', hl } },
        virt_text_pos = 'inline',
        hl_mode = 'combine',
      })
    end
  end
end

api.events.subscribe(api.events.Event.TreeRendered, cut_long_names)
vim.api.nvim_create_autocmd('WinResized', {
  callback = function()
    local win = api.tree.winid()
    if win and vim.tbl_contains(vim.v.event.windows, win) then
      cut_long_names()
      -- The tree keeps the width it was dragged to: nvim-tree would put its
      -- default width back when a file opens or the tree is shown again.
      api.tree.resize({ width = vim.api.nvim_win_get_width(win) })
    end
  end,
})

-- Nothing scrolls the tree sideways, not even `zl` or `$`.
vim.api.nvim_create_autocmd('WinScrolled', {
  callback = function()
    local win = api.tree.winid()
    if win and vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol > 0 then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ leftcol = 0 })
      end)
    end
  end,
})

-- Its text can't be selected either, and it shows no cursor, only the
-- highlighted current line (see modeless.lua).

api.events.subscribe(api.events.Event.TreeOpen, function()
  local win = api.tree.winid()
  if win then
    -- The tree window is split off the editor window and would inherit its
    -- code gutter; give it the default gutter.
    vim.wo[win].statuscolumn = ''
    -- Cut names stay cut on the cursor line too (only there: windows split
    -- off this one don't hide text).
    vim.api.nvim_set_option_value('conceallevel', 2, { scope = 'local', win = win })
    vim.api.nvim_set_option_value('concealcursor', 'nvic', { scope = 'local', win = win })
  end
end)

-- `nvim` or `nvim <dir>` opens the directory as a project: file tree on the
-- left (focused), start screen on the right. `nvim <file>` opens just the file.
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function(data)
    local is_dir = vim.fn.isdirectory(data.file) == 1
    local no_name = data.file == '' and vim.bo[data.buf].buftype == ''
    if not is_dir and not no_name then
      return
    end

    if is_dir then
      vim.cmd.enew()
      vim.cmd.bwipeout(data.buf)
      vim.cmd.cd(data.file)
    end
    local editor = vim.api.nvim_get_current_win()
    api.tree.open()
    require('config.dashboard').open(editor)
  end,
})

-- `:q` quits Neovim from the editor (unless it is split: then just that
-- split closes) and from the tree alike. Floating windows, help and the like
-- still close by themselves.
local quitting = false

-- The `:` command just typed, while it runs: tells a typed `:q` / `:q!`
-- from Ctrl-W q, ZZ and plugins closing their windows, which close just
-- the window as usual.
local typed
vim.api.nvim_create_autocmd('CmdlineLeave', {
  pattern = ':',
  callback = function()
    typed = not vim.v.event.abort and vim.fn.getcmdline() or nil
    vim.schedule(function()
      typed = nil
    end)
  end,
})

vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    local current = vim.api.nvim_get_current_win()
    if quitting or vim.api.nvim_win_get_config(current).relative ~= '' then
      return
    end

    -- The tree: it closes as usual, then everything quits (`:q!` too).
    if vim.bo[vim.api.nvim_win_get_buf(current)].filetype == 'NvimTree' then
      if not typed then
        return
      end
      local bang = typed:match('!%s*$') and '!' or ''
      vim.schedule(function()
        -- Already on the way out (it was `:qa`).
        if vim.v.exiting ~= vim.NIL then
          return
        end
        quitting = true
        local ok, err = pcall(vim.cmd, 'qa' .. bang)
        quitting = false
        if not ok then
          vim.notify((err:gsub('^Vim:', '')), vim.log.levels.ERROR)
        end
      end)
      return
    end

    -- The editor: the other windows close first, so the one `:q` closes is
    -- the last.
    if not util.is_editor_buf(0) then
      return
    end
    local others, editor_wins = {}, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= current and vim.api.nvim_win_get_config(win).relative == '' then
        table.insert(others, win)
        if util.is_editor_buf(vim.api.nvim_win_get_buf(win)) then
          editor_wins = editor_wins + 1
        end
      end
    end
    if editor_wins == 0 then
      for _, win in ipairs(others) do
        vim.api.nvim_win_close(win, true)
      end
    end
  end,
})

-- Cmd+V in the tree pastes files into the folder under the cursor (the
-- folder of the file under it), as in VSCode: files copied in Finder, which
-- Ghostty pastes as their paths, or paths copied here with Cmd+C. A name
-- already there gets " copy", " copy 2"...

-- The files a pasted text names: the whole of it, a path a line, or paths
-- with their blanks and the like escaped by a backslash, apart (Ghostty's).
local function pasted_files(text, root)
  local function full(path)
    return vim.fs.normalize(path:sub(1, 1) == '/' and path or root .. '/' .. path)
  end
  local function existing(paths)
    local files = {}
    for _, path in ipairs(paths) do
      if path ~= '' and vim.uv.fs_stat(full(path)) then
        table.insert(files, full(path))
      end
    end
    return #files == #paths and files or nil
  end
  text = vim.trim(text)
  local escaped = {}
  for path in text:gsub('\\(.)', function(char)
    return char == ' ' and '\0' or '\\' .. char
  end):gmatch('%S+') do
    table.insert(escaped, (path:gsub('%z', ' '):gsub('\\(.)', '%1')))
  end
  return existing({ text }) or existing(vim.split(text, '\n', { trimempty = true })) or existing(escaped)
end

local function free_name(dir, name, is_dir)
  local base, ext = name:match('^(.+)(%.[^.]+)$')
  if is_dir or not base then
    base, ext = name, ''
  end
  local candidate, n = name, 1
  while vim.uv.fs_stat(dir .. '/' .. candidate) do
    candidate = ('%s copy%s%s'):format(base, n > 1 and ' ' .. n or '', ext)
    n = n + 1
  end
  return candidate
end

-- The tree's nodes by line.
local function nodes_by_line()
  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  return explorer and explorer:get_nodes_by_line(core.get_nodes_starting_line()) or {}
end

-- Several files and folders can be selected, as in VSCode: Ctrl+click adds
-- or takes one away (Ghostty passes no Cmd with clicks), Shift+click selects
-- those from the one clicked last to it (with mouse-shift-capture in
-- config.ghostty), a click or Esc leaves none. Deleting, dragging and
-- copying paths act on all of them, else on the one under the cursor.
Snacks.util.set_hl({ ExplorerSelected = 'Visual' }, { default = true })
local select_ns = vim.api.nvim_create_namespace('explorer.selected')
local selected, anchor = {}, nil ---@type table<string, true>, string?
-- A press on a selected one: the selection goes on release, unless it is
-- dragged.
local pressed_on_selection = false

-- Highlights the selected lines, again each time the tree is drawn.
local function draw_selection()
  local win = api.tree.winid()
  if not win then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_buf_clear_namespace(buf, select_ns, 0, -1)
  for line, node in pairs(nodes_by_line()) do
    if selected[node.absolute_path] then
      vim.api.nvim_buf_set_extmark(buf, select_ns, line - 1, 0, { line_hl_group = 'ExplorerSelected', priority = 150 })
    end
  end
end

api.events.subscribe(api.events.Event.TreeRendered, draw_selection)

local function clear_selection()
  selected = {}
  draw_selection()
end

-- What deleting, dragging and copying paths act on: the selected paths,
-- else the one under the cursor; not those inside a selected folder.
local function targets()
  local paths = vim.tbl_keys(selected)
  if #paths == 0 then
    local node = api.tree.get_node_under_cursor()
    if node and node.name ~= '..' and node.absolute_path ~= vim.fn.getcwd() then
      paths = { node.absolute_path }
    end
  end
  table.sort(paths)
  local result = {}
  for _, path in ipairs(paths) do
    if not (#result > 0 and vim.startswith(path, result[#result] .. '/')) then
      table.insert(result, path)
    end
  end
  return result
end

-- The node and line clicked in the tree.
local function clicked()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= api.tree.winid() or pos.line == 0 then
    return
  end
  return nodes_by_line()[pos.line], pos.line
end

-- A click (after the cursor went there).
function M.click()
  local node = clicked()
  pressed_on_selection = node ~= nil and selected[node.absolute_path] == true
  if not pressed_on_selection and next(selected) then
    clear_selection()
  end
  anchor = node and node.absolute_path or anchor
end

function M.ctrl_click()
  local node, line = clicked()
  if not node then
    return
  end
  -- The one clicked before is part of a new selection, as in VSCode.
  if not next(selected) and anchor and anchor ~= node.absolute_path and vim.uv.fs_lstat(anchor) then
    selected[anchor] = true
  end
  selected[node.absolute_path] = not selected[node.absolute_path] or nil
  anchor = node.absolute_path
  vim.api.nvim_win_set_cursor(api.tree.winid(), { line, 0 })
  draw_selection()
end

function M.shift_click()
  local node, line = clicked()
  if not node then
    return
  end
  local win = api.tree.winid()
  local lines = nodes_by_line()
  local from = vim.api.nvim_win_get_cursor(win)[1]
  for each, other in pairs(lines) do
    if other.absolute_path == anchor then
      from = each
    end
  end
  selected = {}
  for each = math.min(from, line), math.max(from, line) do
    if lines[each] then
      selected[lines[each].absolute_path] = true
    end
  end
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  draw_selection()
end

-- A right click keeps the selection when it is on it, else leaves none.
function M.right_click()
  local node = api.tree.get_node_under_cursor()
  if not (node and selected[node.absolute_path]) then
    clear_selection()
  end
end

M.clear_selection = clear_selection
M.targets = targets

-- Cmd+C / Cmd+Shift+C: the paths, from the project's folder or full, a line
-- each.
function M.copy_paths(full)
  local paths = targets()
  if #paths == 0 then
    return
  end
  for i, path in ipairs(paths) do
    paths[i] = full and path or vim.fs.relpath(vim.fn.getcwd(), path) or path
  end
  vim.fn.setreg('+', table.concat(paths, '\n'))
  vim.notify(#paths == 1 and 'Copied ' .. paths[1] or ('Copied %d paths'):format(#paths))
end

-- Cmd+Z / Cmd+Shift+Z in the tree undo and redo the pastes, moves and
-- deletes done here, as in VSCode's explorer: steps of { undo, redo }, each returning
-- the file to show after it, if any.
local done, undone = {}, {}

local function record(step)
  table.insert(done, step)
  undone = {}
end

local function show(path)
  api.tree.reload()
  if path and vim.uv.fs_stat(path) then
    api.tree.find_file({ buf = path, focus = true })
  end
end

function M.undo()
  local step = table.remove(done)
  if not step then
    return vim.notify('Nothing to undo in the tree')
  end
  show(step.undo())
  table.insert(undone, step)
end

function M.redo()
  local step = table.remove(undone)
  if not step then
    return vim.notify('Nothing to redo in the tree')
  end
  show(step.redo())
  table.insert(done, step)
end

-- Closes the tabs of a file, or of the files in a folder, as Cmd+W does
-- (see actions.lua).
local function close_tabs(path)
  local bufs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name == path or vim.startswith(name, path .. '/') then
      table.insert(bufs, buf)
    end
  end
  if #bufs > 0 then
    actions.close_buffers(bufs, true)
  end
end

-- Deletes a pasted copy, and its tabs.
local function remove(path)
  close_tabs(path)
  vim.fs.rm(path, { recursive = true, force = true })
end

-- Cmd+Backspace in the tree (Ghostty sends it as Ctrl+U) moves the file or
-- folder under the cursor to the Trash, as in Finder: its tabs close, and
-- Cmd+Z brings it back. The Trash is ~/.Trash on macOS (Finder's Put Back
-- doesn't know these, Cmd+Z does) and the freedesktop one on Linux. From
-- another disk, the system's trash command moves it, without undo.
local function trash_dir()
  if vim.fn.has('mac') == 1 then
    return vim.fs.normalize('~/.Trash')
  end
  local trash = (vim.env.XDG_DATA_HOME or vim.fs.normalize('~/.local/share')) .. '/Trash'
  vim.fn.mkdir(trash .. '/files', 'p')
  vim.fn.mkdir(trash .. '/info', 'p')
  return trash .. '/files', trash .. '/info'
end

-- Moves path to the Trash; returns where it went (true when that is
-- unknown), or nil.
local function to_trash(path)
  local dir, info = trash_dir()
  local name = vim.fs.basename(path)
  -- A name taken there gets the time, as Finder does: "name 16.44.21.txt".
  local base, ext = name:match('^(.+)(%.[^.]+)$')
  if not base or vim.fn.isdirectory(path) == 1 then
    base, ext = name, ''
  end
  local target, n = dir .. '/' .. name, 1
  while vim.uv.fs_lstat(target) do
    target = ('%s/%s %s%s%s'):format(dir, base, os.date('%H.%M.%S'), n > 1 and ' ' .. n or '', ext)
    n = n + 1
  end
  if vim.uv.fs_rename(path, target) then
    if info then
      local encoded = path:gsub('[^%w%-._~/]', function(char)
        return ('%%%02X'):format(char:byte())
      end)
      local text = { '[Trash Info]', 'Path=' .. encoded, 'DeletionDate=' .. os.date('%Y-%m-%dT%H:%M:%S') }
      vim.fn.writefile(text, info .. '/' .. vim.fs.basename(target) .. '.trashinfo')
    end
    return target
  end
  local cmd = vim.fn.has('mac') == 1 and { 'trash', path } or { 'gio', 'trash', path }
  local ok, result = pcall(vim.system, cmd)
  return ok and result:wait().code == 0 or nil
end

local function from_trash(trashed, path)
  if vim.uv.fs_lstat(path) then
    vim.notify(vim.fs.basename(path) .. ' is there again, the Trash keeps the deleted one', vim.log.levels.WARN)
    return false
  end
  if not vim.uv.fs_rename(trashed, path) then
    return false
  end
  local _, info = trash_dir()
  if info then
    vim.fs.rm(info .. '/' .. vim.fs.basename(trashed) .. '.trashinfo', { force = true })
  end
  return true
end

function M.delete()
  local paths = targets()
  if #paths == 0 then
    return
  end
  -- Each path and where it went in the Trash.
  local trashed, lost = {}, {}
  for _, path in ipairs(paths) do
    close_tabs(path)
    local place = to_trash(path)
    if place == true then
      table.insert(lost, vim.fs.basename(path))
    elseif place then
      table.insert(trashed, { path = path, place = place })
    else
      vim.notify('Couldn\'t move to the Trash: ' .. path, vim.log.levels.ERROR)
    end
  end
  clear_selection()
  show()
  if #lost > 0 then
    vim.notify('Moved to the Trash without undo (another disk): ' .. table.concat(lost, ', '))
  end
  if #trashed > 0 then
    record({
      undo = function()
        local back
        for _, item in ipairs(trashed) do
          back = from_trash(item.place, item.path) and item.path or back
        end
        return back
      end,
      redo = function()
        for _, item in ipairs(trashed) do
          close_tabs(item.path)
          local again = to_trash(item.path)
          item.place = again ~= true and again or item.place
        end
      end,
    })
  end
end

local function paste_files(text)
  local root = api.tree.get_nodes().absolute_path
  local files = pasted_files(text, root)
  if not files then
    return vim.notify('Nothing to paste: no files in the clipboard', vim.log.levels.WARN)
  end
  local node = api.tree.get_node_under_cursor()
  local dir = not node and root or node.type == 'directory' and node.absolute_path or vim.fs.dirname(node.absolute_path)
  local copies = {}
  for _, file in ipairs(files) do
    local is_dir = vim.fn.isdirectory(file) == 1
    if is_dir and (dir == file or vim.startswith(dir, file .. '/')) then
      vim.notify('A folder can\'t be pasted into itself: ' .. file, vim.log.levels.WARN)
    else
      local dest = dir .. '/' .. free_name(dir, vim.fs.basename(file), is_dir)
      local result = vim.system({ 'cp', '-R', file, dest }):wait()
      if result.code == 0 then
        table.insert(copies, { from = file, to = dest })
      else
        vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
    end
  end
  if #copies == 0 then
    return api.tree.reload()
  end
  record({
    undo = function()
      for _, copy in ipairs(copies) do
        remove(copy.to)
      end
    end,
    redo = function()
      for _, copy in ipairs(copies) do
        if vim.uv.fs_stat(copy.from) and not vim.uv.fs_stat(copy.to) then
          vim.system({ 'cp', '-R', copy.from, copy.to }):wait()
        end
      end
      return copies[#copies].to
    end,
  })
  show(copies[#copies].to)
end

-- Dragging a file or folder in the tree moves it to the folder it is
-- dropped on, or the folder of the file it is dropped on, as in VSCode.
-- While it is dragged, its name follows the mouse with where it would go,
-- and that folder is highlighted with all that is in it. Files open in
-- tabs move with it; Cmd+Z moves it back.
Snacks.util.set_hl({ ExplorerDrop = 'Visual' }, { default = true })
local drop_ns = vim.api.nvim_create_namespace('explorer.drop')
local dragging

-- Moves a file or folder; returns whether it did.
local function move(from, to)
  if vim.uv.fs_stat(to) then
    vim.notify(vim.fs.basename(to) .. ' is already there', vim.log.levels.WARN)
    return false
  end
  if not vim.uv.fs_rename(from, to) then
    -- (Onto another disk.)
    local result = vim.system({ 'mv', from, to }):wait()
    if result.code ~= 0 then
      vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      return false
    end
  end
  require('nvim-tree.utils').rename_loaded_buffers(from, to)
  return true
end

-- The ghost: the dragged name, and the folder it would go to.
local function draw_ghost(row, col, dir)
  local root = vim.fn.getcwd()
  local icon = #dragging.paths > 1 and '\u{f0c5}'
    or vim.fn.isdirectory(dragging.paths[1]) == 1 and '\u{f07b}'
    or require('nvim-web-devicons').get_icon(dragging.name, nil, { default = true })
  local where = dir and '  →  ' .. (dir == root and vim.fs.basename(root) or vim.fs.relpath(root, dir) or dir) .. '/' or ''
  local name = (' %s %s'):format(icon, dragging.name)
  vim.api.nvim_buf_set_lines(dragging.buf, 0, -1, false, { name .. where .. ' ' })
  vim.api.nvim_buf_set_extmark(dragging.buf, drop_ns, 0, #name, { end_col = #name + #where, hl_group = 'ExplorerMuted' })
  local width = vim.fn.strdisplaywidth(name .. where .. ' ')
  vim.api.nvim_win_set_config(dragging.win, {
    relative = 'editor',
    row = math.min(row, vim.o.lines - 3),
    col = math.max(0, math.min(col + 1, vim.o.columns - width - 2)),
    width = width,
    height = 1,
  })
end

function M.drag()
  local win = api.tree.winid()
  if not win then
    return
  end
  local pos = vim.fn.getmousepos()
  local lines = nodes_by_line()
  if not dragging then
    -- From the line pressed (the press put the cursor there), once the
    -- mouse has left it.
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local node = lines[line]
    if not node or pos.winid == win and pos.line == line then
      return
    end
    -- The selection when it was pressed on, else that one alone.
    if not selected[node.absolute_path] then
      clear_selection()
    end
    pressed_on_selection = false
    local paths = targets()
    dragging = { paths = paths, name = #paths > 1 and #paths .. ' items' or node.name }
    dragging.buf = vim.api.nvim_create_buf(false, true)
    dragging.win = vim.api.nvim_open_win(dragging.buf, false, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 1,
      height = 1,
      style = 'minimal',
      border = 'rounded',
      focusable = false,
      zindex = 250,
      noautocmd = true,
    })
  end

  local node = pos.winid == win and lines[pos.line]
  local target = node and (node.type == 'directory' and node or node.parent)
  local dir = target and target.absolute_path
  -- Not into one of them, and not where they all are already.
  local moves = false
  for _, path in ipairs(dir and dragging.paths or {}) do
    if dir == path or vim.startswith(dir, path .. '/') then
      moves = false
      break
    end
    moves = moves or vim.fs.dirname(path) ~= dir
  end
  dir = moves and dir or nil
  dragging.target = dir

  local buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_buf_clear_namespace(buf, drop_ns, 0, -1)
  for line, each in pairs(dir and lines or {}) do
    if each.absolute_path == dir or vim.startswith(each.absolute_path, dir .. '/') then
      vim.api.nvim_buf_set_extmark(buf, drop_ns, line - 1, 0, { line_hl_group = 'ExplorerDrop', priority = 200 })
    end
  end
  draw_ghost(pos.screenrow, pos.screencol, dir)
end

-- The end of a click in the tree: a drop when a file was dragged, else
-- click (a chevron's).
function M.release(click)
  if not dragging then
    if pressed_on_selection then
      pressed_on_selection = false
      clear_selection()
    end
    return click()
  end
  local drop = dragging
  dragging = nil
  pcall(vim.api.nvim_win_close, drop.win, true)
  pcall(vim.api.nvim_buf_delete, drop.buf, { force = true })
  local win = api.tree.winid()
  if win then
    vim.api.nvim_buf_clear_namespace(vim.api.nvim_win_get_buf(win), drop_ns, 0, -1)
  end
  if not drop.target then
    return
  end
  local moved = {}
  for _, from in ipairs(drop.paths) do
    local to = drop.target .. '/' .. vim.fs.basename(from)
    if vim.fs.dirname(from) ~= drop.target and move(from, to) then
      table.insert(moved, { from = from, to = to })
    end
  end
  clear_selection()
  if #moved == 0 then
    return show()
  end
  record({
    undo = function()
      local back
      for _, item in ipairs(moved) do
        back = move(item.to, item.from) and item.from or back
      end
      return back
    end,
    redo = function()
      local there
      for _, item in ipairs(moved) do
        there = move(item.from, item.to) and item.to or there
      end
      return there
    end,
  })
  show(moved[#moved].to)
end

local paste = vim.paste
vim.paste = function(lines, phase)
  if vim.bo.filetype ~= 'NvimTree' then
    return paste(lines, phase)
  end
  -- (Big pastes come in chunks.)
  M.pasted = (phase == -1 or phase == 1) and {} or M.pasted or {}
  vim.list_extend(M.pasted, lines)
  if phase == -1 or phase == 3 then
    paste_files(table.concat(M.pasted, '\n'))
    M.pasted = nil
  end
  return true
end

return M
