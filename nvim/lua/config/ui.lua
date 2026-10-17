-- Tabs, git marks, indent guides, pickers and images. No status bar (see
-- options.lua).

local bufferline = require('bufferline')
bufferline.setup({
  options = {
    -- JetBrains-style tabs: on the editor background, the active one
    -- underlined, no italics.
    style_preset = { bufferline.style_preset.minimal, bufferline.style_preset.no_italic },
    indicator = { style = 'underline' },
    -- Closing a tab keeps the window layout; a modified file asks to save.
    close_command = function(buf)
      require('config.actions').close_buffer(buf)
    end,
    -- Right click does nothing (bufferline's own closed the tab).
    right_mouse_command = function() end,
    show_close_icon = false,
    modified_icon = '●',
    -- No tab for the empty buffer nvim starts with.
    custom_filter = function(buf)
      return vim.api.nvim_buf_get_name(buf) ~= '' or vim.bo[buf].modified
    end,
    -- Tabs start right of the tree; the room above it gets the tree's
    -- header (project name and buttons, see tree.lua), put in place of
    -- this character.
    offsets = {
      { filetype = 'NvimTree', text = '\u{F8FF}', text_align = 'left', highlight = 'Normal' },
    },
  },
})

-- Added / changed / deleted lines as thin bars next to the line numbers.
require('gitsigns').setup({
  signs = {
    add = { text = '▎' },
    change = { text = '▎' },
    delete = { text = '▁' },
    topdelete = { text = '▔' },
    changedelete = { text = '▎' },
    untracked = { text = '▎' },
  },
})

require('snacks').setup({
  -- Indent guides, with the current block's guide highlighted.
  indent = { enabled = true, animate = { enabled = false } },
  -- Quick open, search in files, command palette (see keymaps.lua). Esc
  -- closes them right away, as in VSCode.
  picker = {
    enabled = true,
    win = { input = { keys = { ['<Esc>'] = { 'close', mode = { 'n', 'i' } } } } },
  },
  -- Name prompts (new file, rename) in a rounded popup instead of the
  -- command line.
  input = { enabled = true },
  -- Image files open inside nvim in terminals with the kitty graphics
  -- protocol (Ghostty). Images linked from Markdown pop up in a float while
  -- the cursor is on the link, so the source view stays plain text. SVGs
  -- open as images too (snacks' formats plus svg; drawn by rsvg-convert, see
  -- patches/snacks_image.lua).
  image = {
    enabled = true,
    doc = { inline = false },
    formats = {
      'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tiff', 'heic', 'avif',
      'mp4', 'mov', 'avi', 'mkv', 'webm', 'pdf', 'icns', 'svg',
    },
  },
})
require('patches.snacks_image')
-- Image files: fit to the window, zoom by click, scroll (see imageview.lua).
require('config.imageview')
