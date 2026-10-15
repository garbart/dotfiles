-- Status bar, tabs, git marks, indent guides, pickers, terminal and images.

-- A flat status bar with only the cursor position on the right, in the
-- colors of the theme (the jb lualine theme follows light/dark).
require('lualine').setup({
  options = {
    theme = 'jb',
    -- One status bar across the whole screen instead of one per window.
    globalstatus = true,
    section_separators = '',
    component_separators = '',
  },
  sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {},
    lualine_x = {
      function()
        return ('Ln %d, Col %d'):format(vim.fn.line('.'), vim.fn.virtcol('.'))
      end,
    },
    lualine_y = {},
    lualine_z = {},
  },
})

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
    -- Right click: Close / Close Others / Close All (see menu.lua).
    right_mouse_command = function(buf)
      require('config.menu').tab_menu(buf)
    end,
    show_close_icon = false,
    modified_icon = '●',
    -- No tab for the empty buffer nvim starts with.
    custom_filter = function(buf)
      return vim.api.nvim_buf_get_name(buf) ~= '' or vim.bo[buf].modified
    end,
    -- Tabs start right of the tree; the space above the tree stays empty.
    offsets = {
      { filetype = 'NvimTree', text = '', highlight = 'Normal' },
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
  -- The terminal panel (Ctrl+`): no title bar, and the editor background
  -- instead of the lighter one snacks gives its windows.
  terminal = { win = { wo = { winbar = '', winhighlight = '' } } },
  -- Name prompts (new file, rename) in a rounded popup instead of the
  -- command line.
  input = { enabled = true },
  -- Image files open inside nvim in terminals with the kitty graphics
  -- protocol (Ghostty). Images linked from Markdown pop up in a float while
  -- the cursor is on the link, so the source view stays plain text.
  image = { enabled = true, doc = { inline = false } },
})
require('patches.snacks_image')
