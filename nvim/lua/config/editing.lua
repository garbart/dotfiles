-- Syntax highlighting, code folding, auto-closing pairs, Markdown and CSV
-- views.

local treesitter = require('config.treesitter')
if treesitter.available() then
  -- Runs in the background and does nothing when all parsers are built.
  treesitter.install()
end

-- Tree-sitter highlighting and folding wherever there is a parser; other
-- files keep Vim's regex highlighting.
vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    if not pcall(vim.treesitter.start, args.buf) then
      return
    end
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  end,
})

-- Folds start open; statuscolumn.lua draws their chevrons (click or `za` to
-- toggle). A closed fold shows its first line as is.
vim.o.foldlevelstart = 99
vim.o.foldtext = ''
require('config.statuscolumn')

-- Brackets and quotes close themselves.
require('mini.pairs').setup()

-- Pasting (Cmd+V, which Ghostty sends as a bracketed paste) in normal mode
-- puts the text where the cursor is, like VSCode, instead of after it. A
-- line copied whole in nvim (Cmd+C with nothing selected) goes in as a line
-- above the current one, also like VSCode, also while typing. Only
-- single-chunk pastes (all but huge ones) are handled here: nvim's own paste
-- keeps state across chunks.
local paste = vim.paste
vim.paste = function(lines, phase)
  local mode = vim.api.nvim_get_mode().mode
  if phase ~= -1 or (mode ~= 'n' and mode ~= 'i') then
    return paste(lines, phase)
  end
  local reg = vim.fn.getreginfo('"')
  local whole_line = reg.regtype == 'V' and table.concat(lines, '\n') == table.concat(reg.regcontents, '\n') .. '\n'
  if whole_line then
    -- The cursor stays where it was in its (now moved down) line.
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_put(reg.regcontents, 'l', false, false)
    vim.api.nvim_win_set_cursor(0, { row + #reg.regcontents, col })
  elseif mode == 'n' then
    vim.api.nvim_put(lines, 'c', false, false)
    vim.fn.setpos('.', vim.fn.getpos("']"))
  else
    return paste(lines, phase)
  end
  return true
end

-- .md opens as source, like in VSCode. Cmd+Shift+V (VSCode's preview key)
-- or <leader>m switches the current file between source and rendered view,
-- which looks like a GitHub preview (colors in theme.lua): plain headings,
-- H1/H2 on a tint, code in blocks with the language, rounded tables. Nothing
-- goes into the gutter, which is for git marks.
require('render-markdown').setup({
  enabled = false,
  -- Also while typing, which is most of the time (see modeless.lua); the
  -- cursor's line shows its source.
  render_modes = true,
  sign = { enabled = false },
  heading = {
    icons = { '' },
    position = 'inline',
    width = 'block',
    left_pad = 1,
    right_pad = 2,
  },
  code = {
    width = 'block',
    left_pad = 2,
    right_pad = 2,
    min_width = 60,
    border = 'thin',
    inline_pad = 1,
  },
  pipe_table = { preset = 'round', alignment_indicator = '─' },
  quote = { icon = '▎' },
  bullet = { icons = { '•', '◦', '▪', '▫' } },
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(args)
    -- Long lines wrap at word boundaries, like VSCode does for Markdown.
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true

    local opts = { buffer = args.buf, desc = 'Toggle Markdown source/rendered view' }
    vim.keymap.set('n', '<leader>m', '<Cmd>RenderMarkdown buf_toggle<CR>', opts)
    vim.keymap.set({ 'n', 'i', 'x' }, '<D-V>', '<Cmd>RenderMarkdown buf_toggle<CR>', opts)
  end,
})

-- CSV and TSV open as a table, like in a spreadsheet: the columns aligned
-- (only on screen, the file stays as it is, and typing works in the table),
-- each in a color of its own, the header row kept at the top. The delimiter
-- (comma, semicolon, tab or bar) is detected from the file. Cmd+Shift+V or
-- <leader>m switches between the table and the plain text.
require('csvview').setup({
  parser = { delimiter = { ft = { tsv = '\t' }, fallbacks = { ',', ';', '\t', '|' } } },
  view = { display_mode = 'border' },
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'csv', 'tsv' },
  callback = function(args)
    require('csvview').enable(args.buf)

    local opts = { buffer = args.buf, desc = 'Toggle CSV table/text view' }
    vim.keymap.set('n', '<leader>m', '<Cmd>CsvViewToggle<CR>', opts)
    vim.keymap.set({ 'n', 'i', 'x' }, '<D-V>', '<Cmd>CsvViewToggle<CR>', opts)
  end,
})
