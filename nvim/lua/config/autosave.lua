-- Files save themselves, like VSCode with auto save on: right after a change
-- made outside insert mode (paste, delete, undo), a second after typing
-- stops, and when switching files, leaving the editor or closing a tab.
-- Only files that have a name: a new unnamed one still needs a name.

local M = {}

function M.save(buf)
  local bo = vim.bo[buf]
  if not (vim.api.nvim_buf_is_loaded(buf) and bo.modified and bo.buftype == '' and bo.modifiable) then
    return
  end
  if bo.readonly or vim.api.nvim_buf_get_name(buf) == '' then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    -- A file that can't be written stays modified (● on its tab).
    pcall(vim.cmd, 'silent lockmarks update')
  end)
end

function M.save_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.save(buf)
  end
end

local group = vim.api.nvim_create_augroup('dotfiles.autosave', {})
local timer = assert(vim.uv.new_timer())

vim.api.nvim_create_autocmd('TextChangedI', {
  group = group,
  callback = function(args)
    timer:stop()
    timer:start(1000, 0, vim.schedule_wrap(function()
      if vim.api.nvim_buf_is_valid(args.buf) then
        M.save(args.buf)
      end
    end))
  end,
})

vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave', 'BufLeave' }, {
  group = group,
  callback = function(args)
    M.save(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ 'FocusLost', 'QuitPre' }, {
  group = group,
  callback = M.save_all,
})

return M
