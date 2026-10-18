-- Markdown's rendered view (Cmd+Shift+V or <leader>m in a .md file; its
-- looks are in editing.lua and theme.lua) reads like a preview: read-only,
-- with no cursor (text can still be selected and copied, see modeless.lua),
-- and images drawn in place, as wide as the window. A click on an image
-- opens the image file (zoom and scroll, see imageview.lua). In the source
-- view an image pops up while the cursor is on its link, as before.
--
-- Ctrl+click (or Ctrl+right click) on a link follows it, in both views: to
-- a heading of the file (#anchor, named as GitHub names them), another file
-- (a Markdown one opens in the same view, at the heading after #), an image,
-- or a web address (in the browser). Ctrl+- goes back.

local M = {}

-- The character of the cells snacks draws an image over.
local PLACEHOLDER = 0x10EEEE

-- Snacks' images drawn in place, by buffer.
local inline = {} ---@type table<integer, table>

local function images(buf, on)
  if on and not inline[buf] and Snacks.image.terminal.env().placeholders then
    local drawn = Snacks.image.inline.new(buf)
    -- An image still loading has no marks in the buffer yet, so snacks
    -- doesn't see it among those in view: an update right after (as when
    -- the theme switches) would add it a second time.
    local visible = drawn.visible
    drawn.visible = function(self)
      local shown = visible(self)
      for id, placement in pairs(self.imgs) do
        if #(placement.eids or {}) == 0 then
          shown[id] = placement
        end
      end
      return shown
    end
    inline[buf] = drawn
  elseif not on and inline[buf] then
    -- (Snacks has no way to stop them: they stop updating and go.)
    local drawn = inline[buf]
    inline[buf] = nil
    drawn.update = function() end
    pcall(vim.api.nvim_del_augroup_by_name, 'snacks.image.inline.' .. buf)
    for _, placement in pairs(drawn.imgs) do
      placement:close()
    end
  end
end

-- No cursor line in a window showing the view; the window's own setting
-- comes back with another buffer.
local function cursorline(win)
  local view = vim.b[vim.api.nvim_win_get_buf(win)].read_only_view
  if view and vim.w[win].view_cursorline == nil then
    vim.w[win].view_cursorline = vim.wo[win].cursorline
    vim.wo[win].cursorline = false
  elseif not view and vim.w[win].view_cursorline ~= nil then
    vim.wo[win].cursorline = vim.w[win].view_cursorline
    vim.w[win].view_cursorline = nil
  end
end

local function set_view(buf, on)
  if on then
    vim.b[buf].view_modifiable = vim.bo[buf].modifiable
    Snacks.image.doc.hover_close()
  end
  vim.b[buf].read_only_view = on or nil
  vim.api.nvim_buf_call(buf, function()
    vim.cmd.RenderMarkdown(on and 'buf_enable' or 'buf_disable')
  end)
  vim.bo[buf].modifiable = not on and vim.b[buf].view_modifiable ~= false
  images(buf, on)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    cursorline(win)
  end
  require('config.modeless').settle()
end

-- Switches the current Markdown file between its source and rendered view.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  set_view(buf, not vim.b[buf].read_only_view)
end

-- In the rendered view images are in place, not in a popup.
local hover = Snacks.image.doc.hover
Snacks.image.doc.hover = function()
  if vim.b.read_only_view then
    return Snacks.image.doc.hover_close()
  end
  hover()
end

-- Images in place are as wide as the window's text (snacks: 80 columns).
local new_placement = Snacks.image.placement.new
Snacks.image.placement.new = function(buf, src, opts)
  local win = vim.fn.bufwinid(buf)
  if opts and opts.inline and vim.b[buf].read_only_view and win ~= -1 then
    local info = vim.fn.getwininfo(win)[1]
    opts.max_width = info.width - info.textoff
  end
  return new_placement(buf, src, opts)
end

-- Opens a file, in the rendered view if it's Markdown and view is set.
local function open(path, view)
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  if view and vim.bo[buf].filetype == 'markdown' and not vim.b[buf].read_only_view then
    set_view(buf, true)
  end
end

-- The image drawn over a screen cell of win: the nearest image link above
-- it (a click on an image's rows tells the line after them).
local function image_at(win, row, col)
  local drawn = inline[vim.api.nvim_win_get_buf(win)]
  local char = vim.fn.screenstring(row, col)
  if not drawn or char == '' or vim.fn.char2nr(char) ~= PLACEHOLDER then
    return
  end
  local top = vim.fn.line('w0', win)
  local best, best_line
  for _, placement in pairs(drawn.imgs) do
    local line = placement.opts.pos[1]
    local line_row = vim.fn.screenpos(win, line, 1).row
    local above = line_row == 0 and line < top or line_row > 0 and line_row <= row
    if above and (not best_line or line > best_line) then
      best, best_line = placement, line
    end
  end
  return best and best.img.src
end

-- Opens the image under the mouse in the rendered view, if there is one.
-- Returns whether there was.
function M.clicked(pos)
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local src = vim.b[buf].read_only_view and image_at(pos.winid, pos.screenrow, pos.screencol)
  if src then
    open(src)
  end
  return src ~= nil
end

-- Links: what they show, where they go, and their columns on their line
-- (0-based, the end excluded).

local LINKS = {
  inline_link = true,
  image = true,
  uri_autolink = true,
  email_autolink = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
}

-- A reference link's destination: its definition ([label]: destination).
local function reference(buf, label)
  label = vim.fn.tolower(vim.trim(label))
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local name, dest = line:match('^%s*%[(.-)%]:%s*(%S+)')
    if name and vim.fn.tolower(vim.trim(name)) == label then
      return dest
    end
  end
end

local function link(buf, node)
  local type = node:type()
  local row, col, end_row, end_col = node:range()
  local all = vim.treesitter.get_node_text(node, buf)
  local text, dest, label
  for child in node:iter_children() do
    local kind = child:type()
    if kind == 'link_text' or kind == 'image_description' then
      text = vim.treesitter.get_node_text(child, buf)
    elseif kind == 'link_destination' then
      dest = vim.treesitter.get_node_text(child, buf)
    elseif kind == 'link_label' then
      label = vim.treesitter.get_node_text(child, buf):match('^%[(.*)%]$')
    end
  end
  if type == 'uri_autolink' then
    text = all:sub(2, -2)
    dest = text
  elseif type == 'email_autolink' then
    text = all:sub(2, -2)
    dest = 'mailto:' .. text
  elseif type == 'full_reference_link' then
    dest = label and reference(buf, label)
  elseif type ~= 'inline_link' and type ~= 'image' then
    dest = text and reference(buf, text)
  end
  if dest then
    return { text = text or dest, dest = dest, col = col, end_col = end_row == row and end_col or math.huge }
  end
end

-- The links starting on a line (1-based), in their order: Markdown's, and
-- web addresses in plain text.
local function links_on(buf, lnum)
  local links = {}
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if ok and parser then
    parser:parse({ lnum - 1, lnum })
    parser:for_each_tree(function(tree, ltree)
      if ltree:lang() ~= 'markdown_inline' then
        return
      end
      local function walk(node)
        local row, _, end_row = node:range()
        if end_row < lnum - 1 or row > lnum - 1 then
          return
        end
        if LINKS[node:type()] then
          local found = row == lnum - 1 and link(buf, node)
          if found then
            table.insert(links, found)
          end
          return
        end
        for child in node:iter_children() do
          walk(child)
        end
      end
      walk(tree:root())
    end)
  end
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  for col, url in line:gmatch('()(https?://[^%s<>()%[%]]+)') do
    url = url:gsub('[.,;:!?\'"]+$', '')
    local inside = false
    for _, other in ipairs(links) do
      inside = inside or col - 1 >= other.col and col - 1 < other.end_col
    end
    if not inside then
      table.insert(links, { text = url, dest = url, col = col - 1, end_col = col - 1 + #url })
    end
  end
  table.sort(links, function(a, b)
    return a.col < b.col
  end)
  return links
end

-- Text as the rendered view shows it: no emphasis or code marks, blanks
-- collapsed.
local function plain(text)
  return vim.trim((text:gsub('[*_`]', ''):gsub('%s+', ' ')))
end

-- What win shows of a line (1-based), as plain text, with the screen cell of
-- each character: where its rows are, and what's in their cells.
local function shown(win, lnum)
  local info = vim.fn.getwininfo(win)[1]
  local first = vim.fn.screenpos(win, lnum, 1).row
  first = first > 0 and first or info.winrow
  local next_row = lnum < vim.api.nvim_buf_line_count(info.bufnr) and vim.fn.screenpos(win, lnum + 1, 1).row or 0
  local last = next_row > 0 and next_row - 1 or info.winrow + info.height - 1
  local parts, at, size, blank = {}, {}, 0, true
  local function add(char, cell)
    table.insert(parts, char)
    if cell then
      at[cell] = size + 1
    end
    size = size + #char
  end
  for row = first, last do
    for col = info.wincol + info.textoff, info.wincol + info.width - 1 do
      local char = vim.fn.screenstring(row, col)
      if char:match('^%s') or vim.fn.char2nr(char) == PLACEHOLDER then
        if not blank then
          add(' ')
          blank = true
        end
      elseif char ~= '' and not char:match('^[*_`]$') then
        add(char, row .. ':' .. col)
        blank = false
      end
    end
  end
  return table.concat(parts), at
end

-- The link shown at a screen cell in the rendered view, which hides parts
-- of the line (mouse positions don't count them): the links' text found in
-- what the screen shows, one after another, with the icon before each.
local function link_on_screen(win, lnum, links, row, col)
  local text, at = shown(win, lnum)
  local index = at[row .. ':' .. col] or at[row .. ':' .. (col - 1)]
  if not index then
    return
  end
  local from = 1
  for _, l in ipairs(links) do
    local needle = plain(l.text)
    local first, last = text:find(needle, from, true)
    if needle ~= '' and first then
      from = last + 1
      local icon = text:sub(1, first - 1):match('([\238-\244][\128-\191]*) $')
      first = icon and first - #icon - 1 or first
      if index >= first and index <= last then
        return l
      end
    end
  end
end

-- Headings as GitHub names them for #anchors: lowercase, punctuation gone,
-- each blank a dash; a repeated one gets -1, -2...
local function slug(text)
  text = text:gsub('!?%[(.-)%]%b()', '%1'):gsub('<[^>]+>', ''):gsub('[*`]', '')
  local out = {}
  for _, char in ipairs(vim.fn.split(vim.fn.tolower(text), '\\zs')) do
    local code = vim.fn.char2nr(char)
    if char:match('^[%w_-]$') then
      table.insert(out, char)
    elseif char == ' ' then
      table.insert(out, '-')
    elseif
      code >= 0x80
      and not (code <= 0xBF or code == 0xD7 or code == 0xF7)
      and not (code >= 0x2000 and code <= 0x2BFF)
      and not (code >= 0x3000 and code <= 0x303F)
      and not (code >= 0xFE00 and code <= 0xFE0F)
      and code < 0x1F000
    then
      table.insert(out, char)
    end
  end
  return table.concat(out)
end

local function url_decode(text)
  return (text:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- The line (1-based) of a heading, or an HTML anchor (name= or id=).
local function anchor_line(buf, anchor)
  anchor = vim.fn.tolower(url_decode(anchor))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local seen, fence = {}, nil
  for i, line in ipairs(lines) do
    local mark = line:match('^%s*(```)') or line:match('^%s*(~~~)')
    if mark then
      fence = not fence and mark or fence ~= mark and fence or nil
    elseif not fence then
      local text = line:match('^ ? ? ?#+%s+(.-)%s*#*%s*$')
      local under = lines[i + 1] or ''
      if not text and line:match('%S') and under:match('^ ? ? ?[=-]+%s*$') and not line:match('^%s*[-*+|]') then
        text = vim.trim(line)
      end
      if text then
        local name = slug(text)
        local count = seen[name]
        seen[name] = (count or -1) + 1
        if (count and name .. '-' .. (count + 1) or name) == anchor then
          return i
        end
      end
      local lower = vim.fn.tolower(line)
      if lower:find('name="' .. anchor .. '"', 1, true) or lower:find('id="' .. anchor .. '"', 1, true) then
        return i
      end
    end
  end
end

local function go_to(buf, anchor)
  local line = anchor_line(buf, anchor)
  if not line then
    return vim.notify('No heading #' .. anchor, vim.log.levels.WARN)
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd('normal! zt')
end

local function follow(l, buf)
  local dest = vim.trim(l.dest):gsub('^<(.*)>$', '%1')
  if dest:sub(1, 1) == '#' then
    return go_to(buf, dest:sub(2))
  end
  -- A web address or the like: in the browser, or copied where there's
  -- none (over ssh).
  if dest:match('^%a[%w+.-]*:') then
    local _, err = vim.ui.open(dest)
    if err then
      vim.fn.setreg('+', dest)
      vim.notify('No browser here, copied: ' .. dest)
    end
    return
  end
  local path, anchor = dest:match('^([^#]*)#?(.*)$')
  path = url_decode(path)
  -- Relative to the file; from / it's from the repository's root, as on
  -- GitHub (or the file system's, outside one).
  local root = vim.fs.root(buf, '.git')
  if path:sub(1, 1) ~= '/' then
    path = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) .. '/' .. path
  elseif root and vim.uv.fs_stat(root .. path) then
    path = root .. path
  end
  path = vim.fs.normalize(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return vim.notify('No such file: ' .. path, vim.log.levels.WARN)
  elseif stat.type == 'directory' then
    return pcall(function()
      require('nvim-tree.api').tree.find_file({ buf = path, open = true, focus = true })
    end)
  end
  if path ~= vim.api.nvim_buf_get_name(buf) then
    open(path, vim.b[buf].read_only_view)
  end
  if anchor ~= '' then
    go_to(vim.api.nvim_get_current_buf(), anchor)
  end
end

-- Follows the link (or in the rendered view, the image) under the mouse.
function M.follow_at_mouse()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return
  end
  vim.api.nvim_set_current_win(pos.winid)
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local view = vim.b[buf].read_only_view
  local src = view and image_at(pos.winid, pos.screenrow, pos.screencol)
  if src then
    return open(src)
  end
  local links = links_on(buf, pos.line)
  local target
  if view then
    target = link_on_screen(pos.winid, pos.line, links, pos.screenrow, pos.screencol)
  else
    for _, l in ipairs(links) do
      if pos.column - 1 >= l.col and pos.column - 1 < l.end_col then
        target = l
      end
    end
  end
  if target then
    follow(target, buf)
  end
end

-- HTML images (as READMEs have them for GitHub): those in a <picture> are
-- shown for the theme, its <source media="(prefers-color-scheme: dark)">
-- when the background is dark. In the rendered view the HTML of a <picture>
-- or an <img> is hidden, as on GitHub: an empty line stays, the <img>'s
-- (snacks draws the image under it), and one under it. They are found by
-- their text, outside code blocks: right after a paragraph's text, without
-- an empty line, a <picture> is part of the paragraph, not an HTML block.
-- Snacks finds the <img> with the html parser (see treesitter.lua).

-- An attribute's value in a tag's text.
local function attribute(tag, name)
  local _, last, quote = tag:lower():find(name .. '%s*=%s*(["\'])')
  local close = last and tag:find(quote, last + 1, true)
  return close and tag:sub(last + 1, close - 1)
end

-- The <picture>s and lone <img>s of a buffer, by changedtick: each with
-- its start and end (0-based row and column, the end column excluded), the
-- row of its <img>'s end and, for a <picture>, the dark theme's image.
local html_cache = {}

local function html_images(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if html_cache[buf] and html_cache[buf].tick == tick then
    return html_cache[buf].images
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Where each line starts in the text, and which are code.
  local starts, code, fence, offset = {}, {}, nil, 1
  for i, line in ipairs(lines) do
    starts[i] = offset
    offset = offset + #line + 1
    local mark = line:match('^%s*(```)') or line:match('^%s*(~~~)')
    code[i] = fence ~= nil or mark ~= nil
    if mark then
      fence = not fence and mark or fence ~= mark and fence or nil
    end
  end
  local function at(position)
    local row = 1
    while starts[row + 1] and starts[row + 1] <= position do
      row = row + 1
    end
    return row - 1, position - starts[row]
  end

  local text = table.concat(lines, '\n')
  local lower = text:lower()
  local images, picture, from = {}, nil, 1
  while true do
    local first, last, slash, name = lower:find('<%s*(/?)%s*(%a+)[^>]*>', from)
    if not first then
      break
    end
    from = last + 1
    local row, col = at(first)
    local tag = text:sub(first, last)
    if not code[row + 1] then
      if name == 'picture' and slash == '' then
        picture = { from = { row, col } }
      elseif name == 'picture' and picture then
        picture.to = { at(last + 1) }
        if picture.img then
          table.insert(images, picture)
        end
        picture = nil
      elseif name == 'source' and picture then
        local media, srcset = attribute(tag, 'media'), attribute(tag, 'srcset')
        if media and media:find('prefers%-color%-scheme:%s*dark') and srcset then
          picture.dark = srcset:match('^%s*(%S+)')
        end
      elseif name == 'img' then
        local img = (at(last))
        if picture then
          picture.img = img
        else
          table.insert(images, { from = { row, col }, to = { at(last + 1) }, img = img })
        end
      end
    end
  end
  html_cache[buf] = { tick = tick, images = images }
  return images
end

Snacks.image.doc.transforms.html = function(img, ctx)
  if vim.o.background ~= 'dark' or not ctx.pos then
    return
  end
  local row = ctx.pos.node:start()
  for _, image in ipairs(html_images(ctx.buf)) do
    if image.dark and image.from[1] <= row and row <= image.to[1] then
      img.src = image.dark
    end
  end
end

-- Hides the HTML of the images: the lines all in it up to the <img>'s
-- end, and the text of the others. (A line under an image stays: hidden
-- whole, it would make scrolling skip the image instead of going through.)
local function hide_html_images(buf, ns)
  for _, image in ipairs(html_images(buf)) do
    for row = image.from[1], image.to[1] do
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      local first = row == image.from[1] and image.from[2] or 0
      local last = row == image.to[1] and image.to[2] or #line
      if first == 0 and last >= #line and row < image.img then
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_row = row, conceal_lines = '' })
      elseif last > first then
        vim.api.nvim_buf_set_extmark(buf, ns, row, first, { end_col = math.min(last, #line), conceal = '' })
      end
    end
  end
end

-- Tables have a line between their rows, as on GitHub. render-markdown
-- draws one only under the header; it is copied under each row but the last.
local rows_ns = vim.api.nvim_create_namespace('dotfiles.markdown.rows')
local tables = vim.treesitter.query.parse('markdown', '(pipe_table) @table')

local function table_rows(buf, parser)
  local drawn = require('render-markdown.core.ui').ns
  for _, node in tables:iter_captures(parser:parse()[1]:root(), buf) do
    local delimiter, rows = nil, {}
    for child in node:iter_children() do
      if child:type() == 'pipe_table_delimiter_row' then
        delimiter = child:range()
      elseif child:type() == 'pipe_table_row' then
        table.insert(rows, (child:range()))
      end
    end
    local marks = delimiter and vim.api.nvim_buf_get_extmarks(buf, drawn, { delimiter, 0 }, { delimiter, -1 }, { details = true }) or {}
    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details.virt_text_pos == 'overlay' and details.virt_text then
        -- Where the table starts (in a list item, a quote).
        local line = vim.api.nvim_buf_get_lines(buf, delimiter, delimiter + 1, false)[1]
        local text = table.concat(vim.tbl_map(function(chunk)
          return chunk[1]
        end, details.virt_text))
        local line_between = { { (' '):rep(vim.fn.strdisplaywidth(line:sub(1, mark[3]))) }, { text, 'RenderMarkdownTableRow' } }
        for i = 1, #rows - 1 do
          vim.api.nvim_buf_set_extmark(buf, rows_ns, rows[i], 0, { virt_lines = { line_between } })
        end
        break
      end
    end
  end
end

-- What the rendered view adds to render-markdown's, after each of its
-- renders (see editing.lua): lines between table rows, hidden HTML images.
local html_ns = vim.api.nvim_create_namespace('dotfiles.markdown.html')

function M.decorate(buf)
  local view, tick = vim.b[buf].read_only_view, vim.api.nvim_buf_get_changedtick(buf)
  vim.api.nvim_buf_clear_namespace(buf, rows_ns, 0, -1)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not (ok and parser and view) then
    vim.api.nvim_buf_clear_namespace(buf, html_ns, 0, -1)
    vim.b[buf].html_hidden = nil
    return
  end
  -- (After render-markdown's own lines, which come with the part in view.)
  table_rows(buf, parser)
  -- Hidden lines change the layout: only again when the text changed, not
  -- on each render (render-markdown renders on every scroll).
  if vim.b[buf].html_hidden ~= tick then
    vim.api.nvim_buf_clear_namespace(buf, html_ns, 0, -1)
    vim.b[buf].html_hidden = tick
    hide_html_images(buf, html_ns)
  end
end

local group = vim.api.nvim_create_augroup('dotfiles.markdown', {})

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'markdown',
  callback = function(args)
    local opts = { buffer = args.buf, desc = 'Toggle Markdown source/rendered view' }
    vim.keymap.set('n', '<leader>m', M.toggle, opts)
    vim.keymap.set({ 'n', 'i', 'x', 's' }, '<D-V>', M.toggle, opts)
    opts.desc = 'Follow link'
    vim.keymap.set({ 'n', 'i', 'x', 's' }, '<C-LeftMouse>', M.follow_at_mouse, opts)
    vim.keymap.set({ 'n', 'i', 'x', 's' }, '<C-RightMouse>', M.follow_at_mouse, opts)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  group = group,
  callback = function()
    cursorline(vim.api.nvim_get_current_win())
  end,
})

vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  callback = function(args)
    inline[args.buf] = nil
    html_cache[args.buf] = nil
  end,
})

-- A switch between light and dark brings the images for the theme.
vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    vim.schedule(function()
      for _, drawn in pairs(inline) do
        drawn:update()
      end
    end)
  end,
})

return M
