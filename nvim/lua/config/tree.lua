-- File tree on the left, opened for `nvim` and `nvim <dir>`, with a header
-- like the VSCode explorer: project name and action buttons.

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
    require('nvim-tree.api').config.mappings.default_on_attach(buf)
    vim.keymap.set('n', '<LeftRelease>', click_arrow, { buffer = buf, desc = 'Open/close folder' })
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
  -- in the header shows them (see hidden.lua).
  filters = {
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

-- The header: project name, `[SSH: host]` when remote, buttons on the right.
function M.header()
  local name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local host = vim.env.SSH_CONNECTION and vim.uv.os_gethostname():match('^[^.]*')
  local remote = host and (' [SSH: %s]'):format(host) or ''

  local items = {}
  for i, button in ipairs(buttons) do
    local icon = button.icon
    if type(icon) == 'function' then
      icon = icon()
    end
    if icon then
      table.insert(items, ("%%%d@v:lua.require'config.tree'.on_click@%s%%T"):format(i, icon))
    end
  end
  return (' %%#ExplorerTitle#%%<%s%%#ExplorerMuted#%s%%=%s '):format(
    util.escape(name),
    util.escape(remote),
    table.concat(items, '  ')
  )
end

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
    if vim.tbl_contains(vim.v.event.windows, api.tree.winid()) then
      cut_long_names()
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

-- The tree opens as a full-height column on the left, which would squeeze an
-- open terminal panel into the editor's column. Move the panel back below
-- everything, full width, at the height it had.
local function keep_terminal_full_width()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == 'terminal' then
      local height = vim.api.nvim_win_get_height(win)
      vim.api.nvim_win_call(win, function()
        vim.cmd.wincmd('J')
      end)
      vim.api.nvim_win_set_height(win, height)
    end
  end
end

api.events.subscribe(api.events.Event.TreeOpen, function()
  local win = api.tree.winid()
  if win then
    -- The tree window is split off the editor window and would inherit its
    -- code gutter; give it the default gutter, plus the header.
    vim.wo[win].statuscolumn = ''
    vim.wo[win].winbar = "%!v:lua.require'config.tree'.header()"
    -- Cut names stay cut on the cursor line too.
    vim.wo[win].conceallevel = 2
    vim.wo[win].concealcursor = 'nvic'
  end
  keep_terminal_full_width()
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
-- split closes), the tree and the terminal panel alike. Floating windows,
-- help and the like still close by themselves.
local quitting = false

vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    local current = vim.api.nvim_get_current_win()
    if quitting or vim.api.nvim_win_get_config(current).relative ~= '' then
      return
    end

    -- The tree or the terminal panel: it closes as usual, then everything
    -- quits (`:q!` too). Had the editor been closed first, the terminal panel
    -- would be the last window, and snacks puts an empty one in its place.
    local bo = vim.bo[vim.api.nvim_win_get_buf(current)]
    if bo.filetype == 'NvimTree' or bo.buftype == 'terminal' then
      local bang = vim.fn.histget(':', -1):match('!%s*$') and '!' or ''
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

return M
