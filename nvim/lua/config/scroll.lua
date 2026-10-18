-- Mouse wheel and trackpad scrolling as in VSCode: never into empty space.
-- Down stops once the end of the file is at the bottom of the window, and a
-- file that fits doesn't scroll at all. Sideways goes only as far as the
-- longest line on screen needs; the file tree doesn't scroll sideways at all
-- (its long names are cut, see tree.lua). Up works as usual. An image
-- scrolls all four ways (see imageview.lua).

local function step(page, size, option, default)
  return page and size or tonumber(vim.o.mousescroll:match(option .. ':(%d+)')) or default
end

local function scroll_down(page)
  local win = vim.fn.getmousepos().winid
  if win == 0 then
    return
  end

  vim.api.nvim_win_call(win, function()
    local height = vim.fn.getwininfo(win)[1].height
    for _ = 1, step(page, height, 'ver', 3) do
      -- Screen rows from the top line to the end of the file (wrapped lines
      -- and folds included), counted only as far as needed.
      local rows = vim.api.nvim_win_text_height(win, { start_row = vim.fn.line('w0') - 1, max_height = height + 1 }).all
      if rows <= height then
        break
      end
      vim.cmd.normal({ vim.keycode('<C-e>'), bang = true })
    end
  end)
end

local function scroll_sideways(right, page)
  local win = vim.fn.getmousepos().winid
  if win == 0 or vim.wo[win].wrap or vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'NvimTree' then
    return
  end

  vim.api.nvim_win_call(win, function()
    local info = vim.fn.getwininfo(win)[1]
    local width = info.width - info.textoff
    local widest, longest = 0, info.topline
    for lnum = info.topline, info.botline do
      local w = vim.fn.virtcol({ lnum, '$' }) - 1
      if w > widest then
        widest, longest = w, lnum
      end
    end

    local left = vim.fn.winsaveview().leftcol
    local by = step(page, width, 'hor', 6)
    -- Already past the end (the cursor took it there): scrolling further
    -- right stays put, scrolling left works as usual.
    local target = right and math.min(left + by, math.max(widest - width, left)) or math.max(left - by, 0)
    -- The cursor has to stay in view: when its line is too short for that,
    -- it moves to the longest line on screen, as nvim's own scrolling does.
    if target > left and vim.fn.virtcol({ vim.fn.line('.'), '$' }) - 1 <= target then
      vim.api.nvim_win_set_cursor(win, { longest, 0 })
    end
    if target ~= left then
      local keys = target > left and (target - left) .. 'zl' or (left - target) .. 'zh'
      vim.cmd.normal({ keys, bang = true })
    end
  end)
end

-- An image under the mouse (see imageview.lua) scrolls all four ways, by
-- the same steps (Ctrl: a window's worth); Shift turns the wheel sideways.
-- Returns whether there was one.
local function scroll_image(key, mod)
  local win = vim.fn.getmousepos().winid
  if win == 0 then
    return false
  end
  if mod == 'S-' and (key == 'Down' or key == 'Up') then
    key = key == 'Down' and 'Right' or 'Left'
  end
  local page = mod == 'C-'
  local rows = step(page, vim.api.nvim_win_get_height(win), 'ver', 3)
  local cols = step(page, vim.api.nvim_win_get_width(win), 'hor', 6)
  local by = ({ Down = { rows, 0 }, Up = { -rows, 0 }, Right = { 0, cols }, Left = { 0, -cols } })[key]
  return require('config.imageview').scroll(win, by[1], by[2])
end

-- Shift or Ctrl scrolls a whole screen, as without this.
for _, mod in ipairs({ '', 'S-', 'C-' }) do
  local page = mod ~= ''
  local function map(key, fn)
    -- (s: mouse selections are in Select mode, see modeless.lua.)
    vim.keymap.set({ 'n', 'i', 'x', 's' }, ('<%sScrollWheel%s>'):format(mod, key), function()
      if not scroll_image(key, mod) then
        fn()
      end
    end)
  end
  map('Down', function()
    scroll_down(page)
  end)
  map('Left', function()
    scroll_sideways(false, page)
  end)
  map('Right', function()
    scroll_sideways(true, page)
  end)
  -- Up is nvim's own, but for images.
  local up = ('<%sScrollWheelUp>'):format(mod)
  vim.keymap.set({ 'n', 'i', 'x', 's' }, up, function()
    local pos = vim.fn.getmousepos()
    if pos.winid ~= 0 and require('config.imageview').shows(pos.winid) then
      vim.schedule(function()
        scroll_image('Up', mod)
      end)
      return ''
    end
    return up
  end, { expr = true })
end
