-- Fixes for reopening images in snacks.image, applied on top of the snacks
-- version pinned in nvim-pack-lock.json. They mirror two open upstream PRs;
-- delete this file once snacks ships them:
--   https://github.com/folke/snacks.nvim/pull/2964
--   https://github.com/folke/snacks.nvim/pull/2918
--
-- Without them an image only shows the first time it is opened in a session.
-- Opening it again leaves a blank buffer or a stuck "identify loading …".
--
-- Plus SVGs drawn by rsvg-convert, at the end.

local Image = require('snacks.image.image')
local Placement = require('snacks.image.placement')
local terminal = require('snacks.image.terminal')
local ns = vim.api.nvim_create_namespace('snacks.image')

-- Ghostty and kitty free an image once its last placement is deleted, but
-- snacks still treats it as sent and never transmits it again. Free it
-- explicitly and mark it unsent, so the next placement sends the data anew.
local del = Image.del
function Image:del(pid)
  del(self, pid)
  if not next(self.placements) then
    terminal.request({ a = 'd', d = 'I', i = self.id })
    self.sent = false
  end
end

-- A buffer that leaves its last window is marked hidden and stays hidden
-- after it comes back. Unhide it as soon as a window shows it again. Inline
-- images are hidden and shown by snacks.image.inline, so leave them alone.
local update = Placement.update
function Placement:update()
  if self.hidden and not self.opts.inline and #self:wins() > 0 then
    self.hidden = false
  end
  return update(self)
end

-- Upstream's spinner, except that its timer also stops once the placement is
-- closed (it used to run forever and keep redrawing "loading" over the
-- reopened image), and when it stops it removes the spinner and clears the
-- `modified` flag that emptying the buffer had set: otherwise the image tab
-- shows ● and closing it asks to save. Image buffers can't be edited or
-- written anyway.
function Placement:progress()
  if self.opts.inline or self:ready() then
    return
  end
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, {})
  vim.bo[self.buf].modifiable = false
  local timer = assert(vim.uv.new_timer())
  local eid ---@type integer?
  timer:start(
    0,
    80,
    vim.schedule_wrap(function()
      local valid = vim.api.nvim_buf_is_valid(self.buf)
      if self.closed or self:ready() or self.img:failed() or not valid then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        if valid then
          if eid then
            pcall(vim.api.nvim_buf_del_extmark, self.buf, ns, eid)
          end
          vim.bo[self.buf].modified = false
        end
        return
      end
      vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
      eid = vim.api.nvim_buf_set_extmark(self.buf, ns, 0, 0, {
        virt_text = {
          { Snacks.util.spinner(), 'SnacksImageSpinner' },
          { ' ' },
          { self.img._convert:current().name .. ' loading …', 'SnacksImageLoading' },
        },
      })
    end)
  )
end

-- SVGs (files and Markdown images) are drawn by rsvg-convert, from librsvg
-- (see install.sh), as browsers draw them. snacks hands them to ImageMagick,
-- whose own SVG renderer loses gradients and fails on text, and which doesn't
-- pass them on to rsvg-convert by itself; it stays the fallback. snacks keeps
-- its converters, by file type, in a table local to snacks.image.convert,
-- reached here through the upvalues of its functions.
local function upvalue(fn, name)
  for i = 1, math.huge do
    local key, value = debug.getupvalue(fn, i)
    if key == nil or key == name then
      return value
    end
  end
end

-- text with each light-dark(light, dark) CSS color replaced by the one for
-- the current background ('light' and 'dark' may hold parentheses).
local function pick_light_dark(text, dark)
  local out, pos = {}, 1
  while true do
    local from, to = text:find('light%-dark%(', pos)
    if not from then
      table.insert(out, text:sub(pos))
      return table.concat(out)
    end
    table.insert(out, text:sub(pos, from - 1))
    local depth, comma, i = 1, nil, to + 1
    while i <= #text and depth > 0 do
      local char = text:sub(i, i)
      if char == '(' then
        depth = depth + 1
      elseif char == ')' then
        depth = depth - 1
      elseif char == ',' and depth == 1 and not comma then
        comma = i
      end
      i = i + 1
    end
    if not comma then
      table.insert(out, text:sub(from, i - 1))
    else
      local chosen = dark and text:sub(comma + 1, i - 2) or text:sub(to + 1, comma - 1)
      table.insert(out, pick_light_dark(vim.trim(chosen), dark))
    end
    pos = i
  end
end

local BLOCKS = { div = true, p = true, li = true, tr = true }

-- The lines of an HTML label, each a list of runs { text, size, bold }:
-- broken at <br> and at blocks, sized and bolded as the HTML has them.
local function html_lines(html)
  local lines, line = {}, {}
  local stack = { { size = nil, bold = false } }
  local function break_line()
    if #line > 0 then
      table.insert(lines, line)
    end
    line = {}
  end
  for tag, text in html:gmatch('(<[^>]*>)([^<]*)') do
    local closing, name = tag:match('^<(/?)([%w:]+)')
    name = name and name:lower()
    if name and BLOCKS[name] or name == 'br' then
      break_line()
    end
    if closing == '/' then
      if #stack > 1 then
        table.remove(stack)
      end
    elseif name and not tag:find('/>$') then
      local parent = stack[#stack]
      local size = tonumber(tag:match('font%-size:%s*([%d.]+)px'))
      table.insert(stack, {
        size = size and size > 0 and size or parent.size,
        bold = parent.bold or name == 'b' or name == 'strong' or tag:find('font%-weight:%s*bold') ~= nil,
      })
    end
    -- (No-break spaces as plain ones: at the edge of a run rsvg-convert
    -- drops them.)
    text = text:gsub('\194\160', ' '):gsub('%s+', ' ')
    if text ~= '' and not (text == ' ' and #line == 0) then
      local top, last = stack[#stack], line[#line]
      if last and last.size == top.size and last.bold == top.bold then
        last.text = (last.text .. text):gsub('  +', ' ')
      else
        table.insert(line, { text = text, size = top.size, bold = top.bold })
      end
    end
  end
  break_line()
  -- Without the spaces at the ends, and the lines left empty.
  local result = {}
  for _, runs in ipairs(lines) do
    runs[1].text = runs[1].text:gsub('^ ', '')
    runs[#runs].text = runs[#runs].text:gsub(' $', '')
    local text = table.concat(vim.tbl_map(function(run)
      return run.text
    end, runs))
    if vim.trim(text) ~= '' then
      table.insert(result, runs)
    end
  end
  return result
end

-- A draw.io label: its HTML version (which rsvg-convert skips) and the
-- plain-text copy after it, drawn instead. The copy is laid out anew from
-- the HTML: one font size for all its lines loses the small ones (they run
-- out of their box) and bold, and a break by <div> runs words together.
-- Where the HTML has a background of its own (labels on arrows), the copy
-- gets the editor's, which then seems to erase the arrow under it.
local function plain_label(html, plain)
  local from, to, attrs, content = plain:find('^%s*<text([^>]*)>(.-)</text>')
  if not from then
    return plain
  end
  local lines = html_lines(html)
  local x = attrs:match(' x="([^"]+)"')
  local ys = {}
  for y in content:gmatch('<tspan[^>]* y="([^"]+)"') do
    table.insert(ys, tonumber(y))
  end
  if #ys == 0 then
    ys = { tonumber(attrs:match(' y="([^"]+)"')) }
  end
  local base = tonumber(attrs:match('font%-size="([%d.]+)')) or 11
  if #lines > 0 and x and ys[1] then
    -- Line boxes 1.2 font sizes high, baselines a little below their
    -- middles, the block centered where draw.io centered its copy.
    local baselines, top = {}, 0
    for i, runs in ipairs(lines) do
      local size = 0
      for _, run in ipairs(runs) do
        size = math.max(size, run.size or base)
      end
      baselines[i] = top + 0.6 * size + 0.35 * size
      top = top + 1.2 * size
    end
    local shift = (ys[1] + ys[#ys]) / 2 - (baselines[1] + baselines[#baselines]) / 2
    local spans = {}
    for i, runs in ipairs(lines) do
      local parts = {}
      for _, run in ipairs(runs) do
        local style = (run.size and run.size ~= base and (' font-size="%spx"'):format(run.size) or '')
          .. (run.bold and ' font-weight="bold"' or '')
        table.insert(parts, style == '' and run.text or ('<tspan%s>%s</tspan>'):format(style, run.text))
      end
      spans[i] = ('<tspan x="%s" y="%.1f">%s</tspan>'):format(x, baselines[i] + shift, table.concat(parts))
    end
    content = table.concat(spans)
    -- Spaces between runs of different styles stay.
    attrs = ' xml:space="preserve"' .. attrs
  end
  local has_bg = false
  for value in html:gmatch('background%-color:%s*([^;"]+)') do
    has_bg = has_bg or vim.trim(value) ~= 'transparent'
  end
  if has_bg then
    attrs = ' filter="url(#nvim-label-bg)"' .. attrs
  end
  return ('<text%s>%s</text>'):format(attrs, content) .. plain:sub(to + 1)
end

-- The SVG as the current theme shows it, the way browsers (and GitHub) show
-- SVGs made for both, like draw.io's: light-dark() colors picked for the
-- background, labels as above. draw.io's note for viewers without HTML
-- ("Text is not SVG") goes, it would cover a label.
local function themed_svg(src, dest)
  local fd = assert(io.open(src, 'rb'))
  local text = fd:read('*a')
  fd:close()
  local bg = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg or 0

  text = pick_light_dark(text, vim.o.background == 'dark')
  text = text:gsub('<switch>(.-)</switch>', function(inner)
    if inner:find('svg-export-text-problems', 1, true) then
      return ''
    end
    local html_end = select(2, inner:find('</foreignObject>', 1, true))
    if not html_end then
      return nil
    end
    local html = inner:sub(1, html_end)
    return '<switch>' .. html .. plain_label(html, inner:sub(html_end + 1)) .. '</switch>'
  end)
  -- The background: the text's box, a little wider, under it.
  local filter = ('<defs><filter id="nvim-label-bg" x="-0.03" y="-0.1" width="1.06" height="1.2">'
    .. '<feFlood flood-color="#%06x"/><feComposite in="SourceGraphic" operator="over"/></filter></defs>'):format(bg)
  local svg_open = text:find('<svg[%s>]')
  local tag_end = svg_open and text:find('>', svg_open, true)
  if tag_end then
    text = text:sub(1, tag_end) .. filter .. text:sub(tag_end + 1)
  end

  fd = assert(io.open(dest, 'wb'))
  fd:write(text)
  fd:close()
  return dest
end

local Convert = upvalue(require('snacks.image.convert').convert, 'Convert')
local commands = Convert and upvalue(Convert._resolve, 'commands')
if commands then
  commands.svg = {
    -- One image per theme (and version of the file).
    file = function(convert, meta)
      local stat = vim.uv.fs_stat(meta.src)
      local bg = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg or 0
      return convert:tmpfile(('%s-%06x-%d.png'):format(vim.o.background, bg, stat and stat.mtime.sec or 0))
    end,
    cmd = function(step)
      local src = themed_svg(step.meta.src, (step.file:gsub('%.png$', '.svg')))
      return {
        -- At twice the SVG's size, as ImageMagick's density 192 does: sharp
        -- on a Retina screen.
        { cmd = 'rsvg-convert', args = { '--zoom', 2, '--format', 'png', '--output', '{file}', src } },
        { cmd = 'magick', args = { '-density', 192, src .. '[0]', '{file}' } },
      }
    end,
  }
end

-- An SVG open in a tab follows a switch between light and dark.
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function()
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == 'image' and vim.api.nvim_buf_get_name(buf):lower():match('%.svg$') then
          Snacks.image.buf.attach(buf)
        end
      end
    end)
  end,
})
