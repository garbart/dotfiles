-- The gutter left of the code, laid out like in VSCode and JetBrains IDEs:
-- line number, git change bar, then a fold chevron on lines where a block
-- starts. Clicking the chevron folds or unfolds the block.

local M = {}

local OPEN, CLOSED = '\u{f107}', '\u{f105}'

local function fold_mark(lnum)
  if vim.fn.foldclosed(lnum) == lnum then
    return CLOSED
  end
  -- Tree-sitter's fold expression marks the first line of a block with ">N".
  if vim.wo.foldmethod == 'expr' and tostring(vim.treesitter.foldexpr(lnum)):sub(1, 1) == '>' then
    return OPEN
  end
  return ' '
end

local function render()
  -- Wrapped continuation lines get an empty gutter.
  local wrapped = vim.v.virtnum ~= 0
  -- No numbers in a rendered view, like a preview (see markdown.lua); its
  -- hidden lines would make them jump.
  local num = (wrapped or vim.b.read_only_view) and '' or tostring(vim.v.lnum)
  -- Right-aligned numbers, at least three digits wide like in VSCode.
  local width = math.max(#tostring(vim.fn.line('$')), 3)
  local hl = vim.v.relnum == 0 and 'CursorLineNr' or 'LineNr'
  local mark = wrapped and ' ' or fold_mark(vim.v.lnum)
  return ('%%#%s#%s%s %%*%%s%%#FoldColumn#%%@v:lua.require\'config.statuscolumn\'.click@%s%%T%%* '):format(
    hl,
    (' '):rep(width - #num + 1),
    num,
    mark
  )
end

-- Neovim evaluates the gutter of every window with the focused one as the
-- current window; its line count, folds and file type would leak into the
-- others (shifting their numbers when the focus leaves the editor).
function M.render()
  return vim.api.nvim_win_call(vim.g.statusline_winid, render)
end

function M.click(_, _, button)
  if button ~= 'l' then
    return
  end
  local pos = vim.fn.getmousepos()
  vim.api.nvim_win_call(pos.winid, function()
    if vim.fn.foldlevel(pos.line) == 0 then
      return
    end
    local cmd = vim.fn.foldclosed(pos.line) == -1 and 'foldclose' or 'foldopen'
    vim.cmd(('%d%s'):format(pos.line, cmd))
  end)
end

-- Only windows showing a file get this gutter; the tree, terminals and
-- pickers keep their own (an empty 'statuscolumn' means the default one).
vim.api.nvim_create_autocmd('BufWinEnter', {
  callback = function(args)
    local is_file = vim.bo[args.buf].buftype == '' and vim.bo[args.buf].filetype ~= 'NvimTree'
    vim.wo.statuscolumn = is_file and "%!v:lua.require'config.statuscolumn'.render()" or ''
  end,
})

return M
