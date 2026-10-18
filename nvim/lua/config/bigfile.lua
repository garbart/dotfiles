-- Files over 50 MB aren't read when opened, as in VSCode: their tab shows
-- the file's size and a Load button instead (click it or press Enter), which
-- reads the file. A file loaded once opens right away until nvim quits.

local LIMIT = 50 * 1024 * 1024

local M = {}

local group = vim.api.nvim_create_augroup('dotfiles.bigfile', {})
local ns = vim.api.nvim_create_namespace('dotfiles.bigfile')
local loaded = {}

-- Where the button is: line and byte columns (1-based, inclusive).
local BUTTON = ' Load '
local BUTTON_LINE, BUTTON_FROM = 5, 3

local function size(path)
  local stat = path ~= '' and vim.uv.fs_stat(path)
  return stat and stat.type == 'file' and stat.size or 0
end

local function human(bytes)
  local mb = bytes / 1024 / 1024
  return mb >= 1024 and ('%.1f GB'):format(mb / 1024) or ('%d MB'):format(mb)
end

-- Reads the file into its buffer, as if opened normally.
function M.load(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  loaded[path] = true
  vim.api.nvim_clear_autocmds({ group = group, buffer = buf })
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, key in ipairs({ '<CR>', '<LeftRelease>' }) do
    pcall(vim.keymap.del, 'n', key, { buffer = buf })
  end
  vim.bo[buf].modifiable = true
  -- (A file with no type of its own would keep the notice's.)
  vim.bo[buf].filetype = ''
  vim.api.nvim_buf_call(buf, function()
    vim.cmd('edit!')
  end)
  if vim.api.nvim_get_current_buf() == buf then
    vim.cmd.startinsert()
  end
end

-- The buffer's text in place of the file's.
local function show_notice(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local lines = {
    '',
    ('  %s is %s, over the 50 MB that open right away.'):format(vim.fs.basename(path), human(size(path))),
    '  Loading it may take a while and slow the editor down.',
    '',
    (' '):rep(BUTTON_FROM - 1) .. BUTTON,
  }
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  -- Not text: no insert mode, cursor or selection there (see modeless.lua).
  vim.bo[buf].filetype = 'bigfile'
  vim.api.nvim_buf_set_extmark(buf, ns, BUTTON_LINE - 1, BUTTON_FROM - 1, {
    end_col = BUTTON_FROM - 1 + #BUTTON,
    hl_group = 'LoadButton',
  })

  vim.keymap.set('n', '<CR>', function()
    M.load(buf)
  end, { buffer = buf, desc = 'Load the file' })
  vim.keymap.set('n', '<LeftRelease>', function()
    local pos = vim.fn.getmousepos()
    if pos.line == BUTTON_LINE and pos.column >= BUTTON_FROM and pos.column < BUTTON_FROM + #BUTTON then
      M.load(buf)
    end
  end, { buffer = buf, desc = 'Load the file' })
end

-- A big file's buffer gets the notice instead of the file when it is read,
-- and is never written over the file.
local function guard(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if loaded[path] or size(path) <= LIMIT then
    return
  end
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    buffer = buf,
    callback = function(args)
      show_notice(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = buf,
    callback = function(args)
      vim.bo[args.buf].modified = false
    end,
  })
end

vim.api.nvim_create_autocmd('BufNew', {
  group = group,
  callback = function(args)
    guard(args.buf)
  end,
})

-- Files given on the command line have their buffers before this runs.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if not vim.api.nvim_buf_is_loaded(buf) then
    guard(buf)
  end
end

return M
