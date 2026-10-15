-- File tree on the left, opened for `nvim` and `nvim <dir>`, with a header
-- like the VSCode explorer: project name and action buttons.

local actions = require('config.actions')
local util = require('config.util')

local M = {}

require('nvim-tree').setup({
  -- Directories are opened by the VimEnter handler below. The built-in hijack
  -- would turn the whole window into the tree, leaving no editor on the right.
  hijack_directories = { enable = false },
  -- Highlight the current file in the tree, expanding folders up to it.
  update_focused_file = { enable = true },
  filters = { custom = { '^\\.git$' } },
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
    icons = {
      git_placement = 'right_align',
      show = { folder = false },
      glyphs = {
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
-- the tree still reloads it by hand).
local buttons = {
  { icon = '\u{ea7f}', run = actions.new_file },
  { icon = '\u{ea80}', run = actions.new_folder },
  { icon = '\u{eac5}', run = api.tree.collapse_all },
}

-- The header: project name, `[SSH: host]` when remote, buttons on the right.
function M.header()
  local name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local host = vim.env.SSH_CONNECTION and vim.uv.os_gethostname():match('^[^.]*')
  local remote = host and (' [SSH: %s]'):format(host) or ''

  local items = {}
  for i, button in ipairs(buttons) do
    items[i] = ("%%%d@v:lua.require'config.tree'.on_click@%s%%T"):format(i, button.icon)
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

-- `:q` in the last editor window quits Neovim instead of leaving the tree or
-- the terminal panel alone on screen. `:q` inside them closes just them.
vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    if not util.is_editor_buf(0) then
      return
    end

    local others, editor_wins = {}, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == '' then
        if util.is_editor_buf(vim.api.nvim_win_get_buf(win)) then
          editor_wins = editor_wins + 1
        else
          table.insert(others, win)
        end
      end
    end

    if editor_wins == 1 then
      for _, win in ipairs(others) do
        vim.api.nvim_win_close(win, true)
      end
    end
  end,
})

return M
