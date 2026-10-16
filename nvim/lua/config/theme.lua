-- JetBrains colors (jb.nvim) in their light and dark variants.
--
-- Ghostty uses the matching jb-light/jb-dark themes and switches them with
-- macOS. Neovim hears about the switch from the terminal (DEC mode 2031, also
-- over ssh), updates 'background', and the theme is loaded again for it.

-- Terminal windows (:terminal) get the ANSI palette of the Ghostty theme for
-- the current background (ghostty/themes in this repo, next to nvim/), so
-- their colors look the same as in Ghostty itself.
local function load_terminal_palette()
  local config = vim.fn.resolve(vim.fn.stdpath('config'))
  local name = vim.o.background == 'light' and 'jb-light' or 'jb-dark'
  local path = vim.fs.normalize(vim.fs.joinpath(config, '..', 'ghostty', 'themes', name))
  if vim.fn.filereadable(path) == 0 then
    return
  end
  for line in io.lines(path) do
    local n, color = line:match('^palette%s*=%s*(%d+)=(#%x+)')
    if n then
      vim.g['terminal_color_' .. n] = color
    end
  end
end

-- Mixes color a into b (24-bit ints): alpha 0 gives b, 1 gives a.
local function blend(a, b, alpha)
  local out = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local ca, cb = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
    out = out + bit.lshift(math.floor(ca * alpha + cb * (1 - alpha) + 0.5), shift)
  end
  return out
end

-- Markdown's rendered view (render-markdown, see editing.lua), close to a
-- GitHub preview: headings bold in the text color, H1 and H2 on a faint
-- accent tint; code on a faint gray; quotes, bullets and table lines quiet.
local function markdown_colors(get, set)
  local normal, muted, faint = get('Normal'), get('Comment'), get('LineNr')
  local accent = get('Function').fg or normal.fg
  local code_bg = blend(normal.fg, normal.bg, 0.07)

  for level = 1, 6 do
    local heading = { fg = level <= 4 and normal.fg or muted.fg, bold = true }
    set('RenderMarkdownH' .. level, heading)
    set('RenderMarkdownH' .. level .. 'Bg', { bg = normal.bg })
    -- The heading text itself is colored by tree-sitter (jb: pink italic).
    set('@markup.heading.' .. level .. '.markdown', heading)
  end
  set('RenderMarkdownH1Bg', { bg = blend(accent, normal.bg, 0.22) })
  set('RenderMarkdownH2Bg', { bg = blend(accent, normal.bg, 0.12) })

  set('RenderMarkdownCode', { bg = code_bg })
  set('RenderMarkdownCodeInline', { fg = normal.fg, bg = code_bg })
  set('RenderMarkdownCodeInfo', { fg = muted.fg })
  set('RenderMarkdownQuote', { fg = faint.fg })
  set('RenderMarkdownBullet', { fg = muted.fg })
  set('RenderMarkdownDash', { fg = faint.fg })
  set('RenderMarkdownTableHead', { fg = faint.fg })
  set('RenderMarkdownTableRow', { fg = faint.fg })

  -- In both views: quotes in gray and table headers bold, instead of jb's
  -- green quotes and pink italic headers.
  set('@markup.quote.markdown', { fg = muted.fg, italic = true })
  set('@markup.heading.markdown', { fg = normal.fg, bold = true })
end

-- Our colors on top of jb: the explorer header, the start screen, Markdown.
-- Applied on every ColorScheme, from a handler registered before the
-- plugins' own, so render-markdown builds its code block borders from these
-- colors and not from jb's.
local function customize()
  local function get(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  local function set(name, hl)
    vim.api.nvim_set_hl(0, name, hl)
  end
  local normal, muted, faint = get('Normal'), get('Comment'), get('LineNr')
  set('ExplorerTitle', { fg = normal.fg, bold = true })
  set('ExplorerMuted', { fg = muted.fg })
  -- Files git ignores look like the others in the tree, and so do
  -- executables and images (jb puts them on a blue background, which looks
  -- like selected text).
  set('NvimTreeGitFileIgnoredHL', { link = 'NvimTreeFileName' })
  set('NvimTreeGitFolderIgnoredHL', { link = 'NvimTreeFolderName' })
  set('NvimTreeExecFile', { link = 'NvimTreeFileName' })
  set('NvimTreeImageFile', { link = 'NvimTreeFileName' })
  -- The cursor of the tree and the start screen, hidden (see modeless.lua).
  set('HiddenCursor', { blend = 100, nocombine = true })
  -- The Load button of a file too big to open right away (bigfile.lua).
  set('LoadButton', { fg = normal.bg, bg = get('Function').fg, bold = true })
  -- The start screen is a quiet watermark, as in VSCode: a faint logo, plain
  -- labels, muted shortcuts.
  set('SnacksDashboardHeader', { fg = faint.fg })
  set('SnacksDashboardDesc', { fg = normal.fg })
  set('SnacksDashboardKey', { fg = muted.fg })

  markdown_colors(get, set)

  -- clangd's coloring by meaning (see lsp.lua) as jb has it, except that
  -- variables aren't underlined (JetBrains' mark of a reassigned one, which
  -- clangd can't tell).
  local variable = get('@lsp.type.variable')
  variable.underline = nil
  set('@lsp.type.variable', variable)
end

vim.api.nvim_create_autocmd('ColorScheme', { pattern = 'jb', callback = customize })

local function load()
  vim.cmd.colorscheme('jb')
  load_terminal_palette()
end

load()

vim.api.nvim_create_autocmd('OptionSet', {
  pattern = 'background',
  -- The switch arrives inside nvim's own terminal-response handler; without
  -- `nested` the ColorScheme event is suppressed and plugins (tabs, status
  -- bar, git marks) never redefine the colors the theme just cleared.
  nested = true,
  callback = load,
})
