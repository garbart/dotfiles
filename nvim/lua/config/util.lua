-- Helpers shared by the config modules.

local M = {}

-- Whether a buffer belongs to the editor area: files and the start screen,
-- but not the tree, terminals or pickers.
function M.is_editor_buf(buf)
  local bo = vim.bo[buf]
  return bo.filetype ~= 'NvimTree' and (bo.buftype == '' or bo.filetype == 'snacks_dashboard')
end

local function is_editor_win(win)
  return win ~= 0
    and vim.api.nvim_win_get_config(win).relative == ''
    and M.is_editor_buf(vim.api.nvim_win_get_buf(win))
end

-- The editor window of the current tab: the current window if it is one,
-- else the one used last, else any.
function M.editor_win()
  for _, win in ipairs({ vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr('#')) }) do
    if is_editor_win(win) then
      return win
    end
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_win(win) then
      return win
    end
  end
end

-- Text for a statusline/winbar/tabline, with `%` escaped.
function M.escape(text)
  return (text:gsub('%%', '%%%%'))
end

return M
