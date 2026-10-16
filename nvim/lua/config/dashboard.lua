-- The start screen in the editor area, shown when the project opens and
-- after the last tab is closed. Like VSCode's empty editor: the project and
-- its branch, and the main shortcuts in the middle.

local actions = require('config.actions')

local M = {}

local function git_branch(cwd)
  local out = vim.fn.systemlist({ 'git', '-C', cwd, 'branch', '--show-current' })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= '' then
    return out[1]
  end
end

-- Shortcuts shown with their Cmd keys; on this screen the plain letter
-- works as well.
local keys = {
  { key = 'p', desc = 'Go to File', shortcut = '⌘ P', action = actions.quick_open },
  { key = 'f', desc = 'Find in Files', shortcut = '⇧ ⌘ F', action = actions.find_in_files },
  { key = 'c', desc = 'Show All Commands', shortcut = '⇧ ⌘ P', action = actions.commands },
  -- (snacks passes the dashboard to actions; new_file must not get it as dir)
  {
    key = 'n',
    desc = 'New File',
    shortcut = 'N',
    action = function()
      actions.new_file()
    end,
  },
  { key = 'e', desc = 'Toggle Explorer', shortcut = '⌘ B', action = actions.toggle_tree },
}

function M.open(win)
  local cwd = vim.fn.getcwd()

  local project = { { vim.fn.fnamemodify(cwd, ':t'), hl = 'ExplorerTitle' } }
  local branch = git_branch(cwd)
  if branch then
    table.insert(project, { '   \u{e0a0} ' .. branch, hl = 'ExplorerMuted' })
  end

  Snacks.dashboard.open({
    win = win,
    width = 56,
    preset = { keys = keys },
    formats = {
      key = function(item)
        return { { item.shortcut or item.key, hl = 'key' } }
      end,
    },
    sections = {
      { section = 'header' },
      { text = project, align = 'center', padding = 2 },
      { section = 'keys' },
    },
  })
end

return M
