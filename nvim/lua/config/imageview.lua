-- Image files (snacks.image's viewer, see ui.lua) open fit to the window's
-- width, and when bigger than the window they scroll like text: with the
-- wheel or the trackpad, up and down and sideways (Shift+wheel too, see
-- scroll.lua). A click zooms in around the clicked spot: 1.5x, 3x, then
-- back to fit (see modeless.lua). Small images keep their size, centered.
-- Each zoom has the pixels the screen shows: SVGs are drawn anew
-- (rsvg-convert), so their text stays sharp, and photos come from the
-- original file rather than snacks' copy of at most 1920x1080 (shown
-- meanwhile). The other zooms are made in the background once the image
-- is shown, so a click shows them at once.
--
-- How: the terminal draws an image over a grid of cells of at most 297 by
-- 297 (kitty unicode placeholders, which snacks uses too). The zoomed image
-- is cut into tiles that fit, each sent as an image of its own, and the
-- window shows the cells of the part in view. Images in Markdown stay
-- snacks' own.

local M = {}

local ZOOMS = { 1, 1.5, 3 }
-- Cells a placement can have per side: the number of row/column marks.
local MAX_CELLS = 297
-- Pixels a level's tiles are made with at most, all together: the terminal
-- keeps images decoded, 4 bytes a pixel (Ghostty: 320 MB in all).
local MAX_PIXELS = 32e6
-- Raster images snacks shows a copy of, at most 1920x1080 (its magick
-- options); zoomed in, their tiles come from the original.
local RASTER = { jpg = true, jpeg = true, gif = true, bmp = true, webp = true, tiff = true, heic = true, avif = true }

local bit = require('bit')
local terminal = Snacks.image.terminal
local Placement = require('snacks.image.placement')

local function upvalue(fn, name)
  for i = 1, math.huge do
    local key, value = debug.getupvalue(fn, i)
    if key == nil or key == name then
      return value
    end
  end
end

-- The placeholder character and the marks for rows and columns (1-based).
local PLACEHOLDER = upvalue(Placement.render_grid, 'PLACEHOLDER')
local positions = upvalue(Placement.render_grid, 'positions')

local ns = vim.api.nvim_create_namespace('dotfiles.imageview')
local views = {} ---@type table<integer, table>
-- Placement ids of tiles, apart from snacks' own (small numbers).
local next_pid = 0xA00000
-- The terminal's images of tiles made here, by file (snacks' own aren't).
local tile_images = {} ---@type table<string, {id: integer, file: string, sent?: boolean}>
local tile_count = 0

local function window_of(buf)
  local win = vim.fn.bufwinid(buf)
  return win ~= -1 and win or nil
end

-- The window's text area, in cells, once it shows no line numbers and the
-- like (snacks' options for its viewer).
local function text_size(win)
  Snacks.util.wo(win, vim.tbl_extend('force', Snacks.image.config.wo or {}, { cursorline = false }))
  local info = vim.fn.getwininfo(win)[1]
  return info.width - info.textoff, info.height
end

-- Frees the terminal's copies of a level's tiles. A tile that is the whole
-- picture is snacks' own image (Markdown may show it too): only the tile's
-- placement goes.
local function free(view, level)
  for _, tile in ipairs(level.tiles) do
    if tile.img and tile.img.sent then
      if tile.img ~= view.base then
        terminal.request({ a = 'd', d = 'I', i = tile.img.id })
        tile.img.sent = false
      elseif tile.pid then
        terminal.request({ a = 'd', d = 'i', i = tile.img.id, p = tile.pid })
      end
    end
  end
end

local function close(view)
  view.closed = true
  for _, level in pairs(view.levels) do
    free(view, level)
  end
  if vim.api.nvim_buf_is_valid(view.buf) then
    vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
  end
end

-- A cell's size in pixels. A terminal that doesn't tell its size in pixels
-- (some over ssh or tmux) gets snacks' guess.
local function cell_size()
  local cell = terminal.size()
  return cell.cell_width > 0 and cell.cell_width or 9, cell.cell_height > 0 and cell.cell_height or 18
end

-- ImageMagick: version 7, or 6 (Linux distributions) without `magick`.
local function magick(...)
  if vim.fn.executable('magick') == 1 then
    return { 'magick', ... }
  end
  local args = { ... }
  return args[1] == 'identify' and args or { 'convert', ... }
end

-- The level's size in cells: fit to the window's width (or the picture's
-- own width when smaller), times the zoom, the height kept in proportion.
local function geometry(view, zoom, width)
  local cw, ch = cell_size()
  local w, h = view.natural.width, view.natural.height
  local fit = math.min(width, w / cw)
  local cols = math.max(1, math.floor(fit * zoom + 0.5))
  local rows = math.max(1, math.floor(cols * cw * h / w / ch + 0.5))
  return cols, rows
end

local render

-- A zoom level for a window width: its size in cells and its tiles, each
-- at most MAX_CELLS by MAX_CELLS.
local function layout(view, zoom, width)
  local cols, rows = geometry(view, zoom, width)
  local across, down = math.ceil(cols / MAX_CELLS), math.ceil(rows / MAX_CELLS)
  local level = {
    zoom = zoom,
    cols = cols,
    rows = rows,
    tile_cols = math.ceil(cols / across),
    tile_rows = math.ceil(rows / down),
    across = across,
    tiles = {},
  }
  for ty = 0, down - 1 do
    for tx = 0, across - 1 do
      local col, row = tx * level.tile_cols, ty * level.tile_rows
      table.insert(level.tiles, {
        col = col,
        row = row,
        cols = math.min(level.tile_cols, cols - col),
        rows = math.min(level.tile_rows, rows - row),
      })
    end
  end
  return level
end

-- Files on their way, with what to call once they are there.
local making = {} ---@type table<string, function[]>

-- Makes a file by running cmd(path), unless it's there or on its way, then
-- calls done. The command writes a temporary file, renamed once complete:
-- the terminal never gets one half written.
local function make(file, cmd, done)
  if vim.uv.fs_stat(file) then
    return done()
  end
  if making[file] then
    return table.insert(making[file], done)
  end
  making[file] = { done }
  local tmp = file:gsub('%.png$', '.tmp.png')
  local function finish(ok)
    if ok then
      vim.uv.fs_rename(tmp, file)
    else
      vim.uv.fs_unlink(tmp)
    end
    local waiting = making[file]
    making[file] = nil
    for _, fn in ipairs(waiting) do
      fn()
    end
  end
  -- (Fails right away when the program isn't there.)
  local ok = pcall(vim.system, cmd(tmp), {}, vim.schedule_wrap(function(result)
    finish(result.code == 0)
  end))
  if not ok then
    vim.schedule(function()
      finish(false)
    end)
  end
end

-- Set once rsvg-convert couldn't draw a tile (too old for --left and the
-- like): SVG tiles are cut from then on.
local draw_fails = false

-- Gets the files of a level's tiles, then calls done. Snacks' copy of the
-- picture serves as the one tile when it has the pixels the screen shows;
-- other tiles are made, kept with snacks' files (a PNG is shown from where
-- it is) and named after the picture as it is now: an SVG drawn anew tile
-- by tile, so its text stays sharp, other pictures cut by ImageMagick from
-- the original (see RASTER) or snacks' copy. They have as many pixels as
-- their cells on screen (all of a level up to MAX_PIXELS), and no more
-- than the picture has.
--
-- The terminal fits each tile into its cells keeping its proportions, so a
-- tile is the part of the picture that its cells cover when the whole of
-- it is fit into all the cells (transparent past the picture's edges):
-- tiles cut by the picture's pixels alone would leave gaps where they meet.
--
-- Tiles that can't be made (rsvg-convert too old for --left and the like,
-- an original ImageMagick can't read) are cut from snacks' copy, and are
-- from then on.
local function make_tiles(view, level, done, from)
  local cw, ch = cell_size()
  local base, original = view.base.file, view.original
  local svg = base:gsub('%.png$', '.svg')
  local aspect = view.natural.width / view.natural.height
  -- The picture's width on screen, and in the pixels it is made with.
  local width = math.min(level.cols * cw, level.rows * ch * aspect)
  local w = width * math.min(1, math.sqrt(MAX_PIXELS / (level.cols * cw * level.rows * ch)))
  if not from then
    if vim.fn.filereadable(svg) == 1 and not draw_fails and vim.fn.executable('rsvg-convert') == 1 then
      from = 'svg'
    elseif original and view.size.width < math.min(w, original.width) - 0.5 then
      from = 'original'
    else
      from = 'base'
    end
  end
  if #level.tiles == 1 and (from == 'base' or view.size.width >= w - 0.5) then
    level.tiles[1].file = base
    return done()
  end
  -- The picture's own width, in pixels.
  local own = from == 'original' and original.width or from == 'base' and view.size.width or math.huge
  w = math.min(w, own)
  local h = w / aspect
  -- Pixels per cell, and where the picture starts in the cells.
  local px, py = cw * w / width, ch * w / width
  local x_off, y_off = (level.cols * px - w) / 2, (level.rows * py - h) / 2
  local source = from == 'svg' and svg or from == 'original' and original.path or base
  local stat = vim.uv.fs_stat(source)
  local key = vim.fn.sha256(source .. (stat and stat.mtime.sec .. ':' .. stat.size or '')):sub(1, 16)
  local function round(x)
    return math.floor(x + 0.5)
  end

  local pending = #level.tiles
  local function made()
    pending = pending - 1
    if pending > 0 then
      return
    end
    for _, tile in ipairs(level.tiles) do
      if from ~= 'base' and not vim.uv.fs_stat(tile.file) then
        draw_fails = draw_fails or from == 'svg'
        if from == 'original' then
          view.original = nil
        end
        return make_tiles(view, level, done, 'base')
      end
    end
    done()
  end
  for _, tile in ipairs(level.tiles) do
    -- The tile in the pixels made: where it starts in the picture, its size.
    local x, y = tile.col * px - x_off, tile.row * py - y_off
    local tw, th = round(tile.cols * px), round(tile.rows * py)
    if from == 'svg' then
      local part = ('%dx%d%+d%+d'):format(tw, th, round(x), round(y))
      tile.file = ('%s/imageview-%s.w%d.%s.png'):format(Snacks.image.config.cache, key, round(w), part)
      make(tile.file, function(out)
        -- (Lengths with = and a unit: negative ones would read as options.)
        return {
          'rsvg-convert',
          '--width=' .. round(w),
          '--keep-aspect-ratio',
          ('--left=%dpx'):format(-round(x)),
          ('--top=%dpx'):format(-round(y)),
          ('--page-width=%dpx'):format(tw),
          ('--page-height=%dpx'):format(th),
          '--format=png',
          '--output=' .. out,
          svg,
        }
      end, made)
    else
      -- The same part in the picture's own pixels, scaled to the tile's.
      local r = own / w
      local part = ('%dx%d%+d%+d'):format(round(tile.cols * px * r), round(tile.rows * py * r), round(x * r), round(y * r))
      tile.file = ('%s/imageview-%s.%s.%dx%d.png'):format(Snacks.image.config.cache, key, part, tw, th)
      make(tile.file, function(out)
        -- (The first frame of a GIF and the like.)
        local cmd = magick(source .. '[0]', '-alpha', 'set', '-background', 'none', '-extent', part, '+repage')
        if math.abs(r - 1) > 1e-3 then
          vim.list_extend(cmd, { '-resize', ('%dx%d!'):format(tw, th) })
        end
        table.insert(cmd, out)
        return cmd
      end, made)
    end
  end
end

-- Sends a tile's file to the terminal as snacks does: its path, or over
-- ssh its data in chunks.
local function send(img)
  img.sent = true
  if not terminal.env().remote then
    return terminal.request({ t = 'f', i = img.id, f = 100, data = Snacks.util.base64(img.file) })
  end
  local fd = assert(io.open(img.file, 'rb'))
  local data = Snacks.util.base64(fd:read('*a'))
  fd:close()
  for offset = 1, #data, 4096 do
    local chunk = data:sub(offset, offset + 4095)
    local more = offset + 4096 <= #data and 1 or 0
    terminal.request(offset == 1 and { t = 'd', i = img.id, f = 100, m = more, data = chunk } or { m = more, data = chunk })
    vim.uv.sleep(1)
  end
end

-- Gets a zoom level ready for the window's width: its tiles made, sent to
-- the terminal and placed, each as big as its cells. Calls done once it is.
-- With from = 'base', its tiles come from snacks' copy (see make_tiles).
local function prepare(view, zoom, width, done, from)
  local key = zoom .. 'x' .. width .. (from or '')
  local level = view.levels[key]
  if level then
    if level.ready then
      done(level)
    else
      table.insert(level.waiting, done)
    end
    return
  end
  level = layout(view, zoom, width)
  level.waiting = { done }
  view.levels[key] = level
  make_tiles(view, level, function()
    if view.closed or view.levels[key] ~= level then
      return
    end
    for _, tile in ipairs(level.tiles) do
      if tile.file == view.base.file then
        tile.img = view.base
        if not tile.img.sent then
          tile.img:send()
        end
      elseif vim.uv.fs_stat(tile.file) then
        -- Image ids of this nvim as snacks makes them (see snacks.image.image),
        -- counted down from the top, where snacks' own count up.
        if not tile_images[tile.file] then
          tile_count = tile_count + 1
          local id = bit.bor(bit.band(view.base.id, 0xFFC000), 0x3FFF - tile_count % 0x2000)
          tile_images[tile.file] = { id = id, file = tile.file }
        end
        tile.img = tile_images[tile.file]
        if not tile.img.sent then
          send(tile.img)
        end
      end
      if tile.img then
        next_pid = next_pid + 1
        tile.pid = next_pid
        tile.hl = 'DotfilesImageTile' .. tile.pid
        -- (Set again after a theme change, as snacks' own.)
        Snacks.util.set_hl({ [tile.hl] = { fg = tile.img.id, sp = tile.pid, nocombine = true } })
        terminal.request({ a = 'p', U = 1, i = tile.img.id, p = tile.pid, C = 1, c = tile.cols, r = tile.rows })
      end
    end
    level.ready = true
    for _, fn in ipairs(level.waiting) do
      fn(level)
    end
    level.waiting = {}
  end, from)
end

-- Makes the tiles of the other zoom levels for the window's width ahead,
-- one level after another from the next one, so that a click shows them
-- at once. Not while the window is still being resized.
local function make_ahead(view, width)
  local token = {}
  view.ahead = token
  vim.defer_fn(function()
    local index = 1
    for i, zoom in ipairs(ZOOMS) do
      if zoom == view.zoom then
        index = i
      end
    end
    local function next_level(step)
      if view.closed or view.ahead ~= token or step >= #ZOOMS then
        return
      end
      local zoom = ZOOMS[(index + step - 1) % #ZOOMS + 1]
      make_tiles(view, layout(view, zoom, width), function()
        next_level(step + 1)
      end)
    end
    next_level(1)
  end, 300)
end

-- Keeps the part in view within the picture.
local function clamp(view, level, width, height)
  view.left = math.max(0, math.min(view.left, level.cols - width))
  view.top = math.max(0, math.min(view.top, level.rows - height))
end

-- Draws the part of the picture in view: one line of placeholder cells per
-- window row, each cell marked with its row and column in its tile.
render = function(view)
  local win = window_of(view.buf)
  local level = view.level
  if not (win and level and level.ready) then
    return
  end
  local width, height = text_size(win)
  clamp(view, level, width, height)
  -- A picture smaller than the window sits in its middle.
  local pad_x = math.max(0, math.floor((width - level.cols) / 2))
  local pad_y = math.max(0, math.floor((height - level.rows) / 2))

  local buf = view.buf
  if vim.api.nvim_buf_line_count(buf) ~= height then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(('\n'):rep(height - 1), '\n'))
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local last_col = math.min(level.cols, view.left + width - pad_x) - 1
  for screen_row = 0, height - 1 do
    local row = view.top + screen_row - pad_y
    if row >= 0 and row < level.rows then
      local chunks = { { (' '):rep(pad_x) } }
      local tile_row = math.floor(row / level.tile_rows)
      local run, run_tile = {}, nil
      for col = view.left, last_col do
        local tile = level.tiles[tile_row * level.across + math.floor(col / level.tile_cols) + 1]
        if tile ~= run_tile and run_tile then
          table.insert(chunks, { table.concat(run), run_tile.hl })
          run = {}
        end
        run_tile = tile
        -- (A tile that couldn't be made shows nothing.)
        table.insert(run, tile.hl and PLACEHOLDER .. positions[row - tile.row + 1] .. positions[col - tile.col + 1] or ' ')
      end
      if run_tile then
        table.insert(chunks, { table.concat(run), run_tile.hl })
      end
      vim.api.nvim_buf_set_extmark(buf, ns, screen_row, 0, { virt_text = chunks, virt_text_pos = 'overlay' })
    end
  end
end

-- Shows the zoom level for the window's width, then calls after (if given).
-- Only the last one asked for is shown, once ready (quick clicks, or the
-- window resized meanwhile); the terminal drops the others. A preview
-- (snacks' copy) shows the level asked for last until it is ready.
local function show(view, zoom, after, preview)
  local win = window_of(view.buf)
  if not win then
    return
  end
  local width = text_size(win)
  if not preview then
    view.want = { zoom = zoom, width = width }
  end
  prepare(view, zoom, width, function(level)
    if view.closed or view.want.zoom ~= zoom or view.want.width ~= width or preview and view.want.shown then
      return
    end
    view.want.shown = not preview
    view.zoom, view.level = zoom, level
    if after then
      after(level)
    end
    render(view)
    for key, other in pairs(view.levels) do
      if other ~= level and other.ready then
        free(view, other)
        view.levels[key] = nil
      end
    end
    make_ahead(view, width)
  end, preview and 'base' or nil)
end

-- Opens the viewer for a buffer's image file.
function M.attach(buf, file)
  if views[buf] then
    close(views[buf])
  end
  local view = { buf = buf, levels = {}, zoom = 1, top = 0, left = 0 }
  views[buf] = view
  view.base = Snacks.image.image.new(file)
  -- The original's size, when snacks shows a copy of it (see RASTER).
  local cmd = magick('identify', '-ping', '-format', '%w %h', file .. '[0]')
  if RASTER[vim.fn.fnamemodify(file, ':e'):lower()] and view.base.file ~= file and vim.fn.executable(cmd[1]) == 1 then
    view.identifying = true
    vim.system(cmd, {}, vim.schedule_wrap(function(result)
      local w, h = (result.stdout or ''):match('^(%d+) (%d+)')
      if result.code == 0 and w then
        view.original = { path = file, width = tonumber(w), height = tonumber(h) }
      end
      view.identifying = false
    end))
  end
  -- Once snacks has converted it (an SVG, a PDF page...) and knows its size.
  local timer = assert(vim.uv.new_timer())
  timer:start(0, 30, vim.schedule_wrap(function()
    if view.closed or not vim.api.nvim_buf_is_valid(buf) then
      timer:close()
      return
    end
    if view.base:ready() and view.base.info and not view.identifying then
      timer:close()
      view.size = view.base.info.size
      view.natural = view.original or view.size
      show(view, 1)
      -- A big photo takes a moment to be made from the original.
      if view.original then
        show(view, 1, nil, true)
      end
    elseif view.base._convert and view.base._convert:error() then
      timer:close()
    end
  end))
end

-- The view in a window, if it shows one.
local function view_in(win)
  local view = win and vim.api.nvim_win_is_valid(win) and views[vim.api.nvim_win_get_buf(win)]
  return view and view.level and view or nil
end

-- Whether win shows an image.
function M.shows(win)
  return view_in(win) ~= nil
end

-- Scrolls the image in win, if it shows one: by rows down (negative: up)
-- and columns right (negative: left). Returns whether it did.
function M.scroll(win, rows, cols)
  local view = view_in(win)
  if not view then
    return false
  end
  view.top, view.left = view.top + rows, view.left + cols
  render(view)
  return true
end

-- A click on the image in win (1-based row and column in its text area):
-- the next zoom, keeping the clicked spot where it is. Returns whether it
-- was one.
function M.click(win, row, col)
  local view = view_in(win)
  if not view then
    return false
  end
  local level = view.level
  local width, height = text_size(win)
  local pad_x = math.max(0, math.floor((width - level.cols) / 2))
  local pad_y = math.max(0, math.floor((height - level.rows) / 2))
  -- The spot, as a fraction of the picture.
  local fx = math.max(0, math.min(1, (view.left + col - 1 - pad_x + 0.5) / level.cols))
  local fy = math.max(0, math.min(1, (view.top + row - 1 - pad_y + 0.5) / level.rows))
  -- (After the one still coming, for quick clicks.)
  local index = 1
  for i, zoom in ipairs(ZOOMS) do
    if zoom == view.want.zoom then
      index = i % #ZOOMS + 1
    end
  end
  show(view, ZOOMS[index], function(new)
    view.left = math.floor(fx * new.cols - (col - 1) + 0.5)
    view.top = math.floor(fy * new.rows - (row - 1) + 0.5)
  end)
  return true
end

-- Takes over snacks' viewer for image files (not the images in Markdown).
local Buf = require('snacks.image.buf')
local attach = Buf._attach
function Buf._attach(buf, opts)
  opts = opts or {}
  local file = opts.src or vim.api.nvim_buf_get_name(buf)
  if opts.src or not Snacks.image.supports(file) then
    return attach(buf, opts)
  end
  Snacks.image.placement.clean(buf)
  Snacks.util.bo(buf, { filetype = 'image', modifiable = false, modified = false, swapfile = false })
  -- Each click counts, also when they come quickly (double clicks).
  for _, key in ipairs({ '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>' }) do
    vim.keymap.set('n', key, function()
      local pos = vim.fn.getmousepos()
      M.click(pos.winid, pos.winrow, pos.wincol)
    end, { buffer = buf })
  end
  M.attach(buf, file)
end

local group = vim.api.nvim_create_augroup('dotfiles.imageview', {})

vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
  group = group,
  callback = function(args)
    if views[args.buf] then
      close(views[args.buf])
      views[args.buf] = nil
    end
  end,
})

-- Drawn again when shown again, and laid out again for a new width.
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized', 'VimResized' }, {
  group = group,
  callback = function()
    vim.schedule(function()
      for _, view in pairs(views) do
        local win = window_of(view.buf)
        if win and view.level then
          show(view, view.want.zoom)
        end
      end
    end)
  end,
})

return M
