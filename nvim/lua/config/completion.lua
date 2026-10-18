-- Completion as in VSCode, by blink.cmp: suggestions show up while typing,
-- from clangd in C and C++ (see lsp.lua) and from the words of the open
-- files elsewhere, with the documentation of the selected one next to them.
-- A completed function gets its parameters as placeholders (Tab goes to the
-- next one), and while its arguments are typed their names show above.
--
-- Enter or Tab accepts, Up / Down choose, Esc closes the list (a second Esc
-- gives normal mode), Ctrl+Space opens it.

require('blink.cmp').setup({
  keymap = {
    preset = 'none',
    ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
    ['<CR>'] = { 'accept', 'fallback' },
    ['<Tab>'] = { 'accept', 'snippet_forward', 'fallback' },
    ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
    ['<Up>'] = { 'select_prev', 'fallback' },
    ['<Down>'] = { 'select_next', 'fallback' },
    ['<Esc>'] = { 'cancel', 'fallback' },
  },
  completion = {
    -- The first suggestion is selected, but only typed in on accept.
    list = { selection = { preselect = true, auto_insert = false } },
    menu = { border = 'rounded' },
    documentation = { auto_show = true, auto_show_delay_ms = 200, window = { border = 'rounded' } },
  },
  signature = { enabled = true, window = { border = 'rounded' } },
  -- The command line keeps nvim's own completion (Tab).
  cmdline = { enabled = false },
  -- The fast matcher is a prebuilt library blink.cmp downloads for its
  -- release; without it (no network) the Lua one is used, silently.
  fuzzy = { implementation = 'prefer_rust' },
})
