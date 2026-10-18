-- An easter egg on the start screen: the Konami code (↑ ↑ ↓ ↓ ← → ← → B A,
-- typed there or in the tree next to it, in any layout) crashes nvim, or so
-- it seems. The screen glitches, a Linux kernel panic runs down, the machine
-- reboots (BIOS, GRUB, systemd, the login) and the editor is back. Keys
-- and clicks do nothing while it plays.

local M = {}

local SEQUENCE = { '<Up>', '<Up>', '<Down>', '<Down>', '<Left>', '<Right>', '<Left>', '<Right>', 'b', 'a' }
local FPS = 30

-- A console's colors, in light and dark themes alike.
local COLORS = {
  KonamiText = { fg = '#c7c7c7', bg = '#000000' },
  KonamiBright = { fg = '#ffffff', bg = '#000000', bold = true },
  KonamiDim = { fg = '#808080', bg = '#000000' },
  KonamiOk = { fg = '#4ec94e', bg = '#000000', bold = true },
  KonamiFail = { fg = '#ff5555', bg = '#000000', bold = true },
  KonamiSelected = { fg = '#000000', bg = '#c7c7c7' },
  KonamiRed = { fg = '#ff3355', bg = '#000000' },
  KonamiCyan = { fg = '#33fff0', bg = '#000000' },
}

-- What the plugins are, for systemd.
local SERVICES = {
  ['nvim-tree.lua'] = 'File Explorer',
  ['bufferline.nvim'] = 'Tabs',
  ['snacks.nvim'] = 'Pickers and Images',
  ['gitsigns.nvim'] = 'Git Marks',
  ['blink.cmp'] = 'Completion',
  ['nvim-treesitter'] = 'Syntax Trees',
  ['render-markdown.nvim'] = 'Markdown Preview',
  ['jb.nvim'] = 'JetBrains Colors',
  ['mini.pairs'] = 'Closing Brackets',
  ['csvview.nvim'] = 'CSV Tables',
  ['nvim-web-devicons'] = 'Icons',
}

local function plugins()
  local names = {}
  local ok, list = pcall(vim.pack.get)
  for _, plugin in ipairs(ok and list or {}) do
    table.insert(names, plugin.spec.name)
  end
  table.sort(names)
  return names
end

local function module_name(plugin)
  return (plugin:gsub('%.nvim$', ''):gsub('%.lua$', ''):gsub('[.-]', '_'))
end

local function version()
  local v = vim.version()
  return ('%d.%d.%d'):format(v.major, v.minor, v.patch)
end

local function host()
  return vim.uv.os_gethostname():match('^[^.]*'):lower()
end

-- A line of segments: { text, highlight } each.
local function line(...)
  return { ... }
end

-- The scenes, each { frames = how long, draw = function(frame) -> lines }.

-- What was on the screen, as rows of cells, for the glitch.
local function capture()
  local rows = {}
  for r = 1, vim.o.lines do
    local cells = {}
    for c = 1, vim.o.columns do
      local char = vim.fn.screenstring(r, c)
      if char ~= '' then
        table.insert(cells, char)
      end
    end
    rows[r] = cells
  end
  return rows
end

local function glitch(shot)
  local NOISE = { '░', '▒', '▓', '█', '#', '%', '&', '?', '$', '@' }
  return {
    frames = 30,
    draw = function(frame)
      local out = {}
      -- More of it goes dark towards the end.
      local dark = math.max(0, frame - 18) / 12
      for r, cells in ipairs(shot) do
        local roll = math.random()
        if roll < dark then
          out[r] = {}
        elseif roll < dark + 0.25 then
          local shift = math.random(-12, 12)
          local moved = {}
          for c = 1, #cells do
            moved[c] = cells[c - shift] or ' '
          end
          out[r] = line({ table.concat(moved), math.random() < 0.5 and 'KonamiRed' or 'KonamiCyan' })
        elseif roll < dark + 0.35 then
          local from, length = math.random(#cells), math.random(5, 40)
          local noisy = {}
          for c = 1, #cells do
            noisy[c] = c >= from and c < from + length and NOISE[math.random(#NOISE)] or cells[c]
          end
          out[r] = line({ table.concat(noisy), 'KonamiText' })
        else
          out[r] = line({ table.concat(cells), 'KonamiDim' })
        end
      end
      return out
    end,
  }
end

-- Lines that come in bursts, as a console prints them: a few in a row,
-- then a pause (from 1 to slowest frames apart), scrolling up when they fill
-- the screen; then they stay for hold frames.
local function scrolling(lines, hold, slowest)
  local at, frame = {}, 0
  for i = 1, #lines do
    at[i] = frame
    frame = frame + (math.random() < 0.3 and math.random(4, slowest) or math.random(1, 3))
  end
  return {
    frames = frame + hold,
    draw = function(now)
      local shown = 0
      while shown < #lines and at[shown + 1] <= now do
        shown = shown + 1
      end
      return vim.list_slice(lines, math.max(1, shown - vim.o.lines + 1), shown)
    end,
  }
end

local function panic()
  local modules = table.concat(vim.tbl_map(module_name, plugins()), ' ')
  local body = {
    'BUG: kernel NULL pointer dereference, address: 0000000000000000',
    '#PF: supervisor read access in kernel mode',
    '#PF: error_code(0x0000) - not-present page',
    'PGD 0 P4D 0',
    'Oops: 0000 [#1] PREEMPT SMP NOPTI',
    'CPU: 7 PID: 1 Comm: nvim Not tainted 6.13.0-konami #1',
    'Hardware name: Ghostty/Konami, BIOS ↑↑↓↓←→←→BA 05/22/1986',
    'RIP: 0010:vim_leave_insert_mode+0x2a/0x90',
    'Code: 0f 1f 44 00 00 55 48 89 e5 41 57 41 56 49 89 fe 41 55 41 54 53 <48> 8b 07',
    'RSP: 0018:ffffb1a0c00a7d48 EFLAGS: 00010246',
    'RAX: 0000000000000000 RBX: ffff8f3a40c1e000 RCX: 0000000000000000',
    'RDX: 000000000000001e RSI: 0000000000000042 RDI: ffff8f3a40c1e000',
    'RBP: ffffb1a0c00a7d70 R08: 0000000000000000 R09: 0000000000000000',
    'Call Trace:',
    ' <TASK>',
    ' ? __die+0x24/0x70',
    ' ? page_fault_oops+0x15b/0x4a0',
    ' ? konami_code_entered+0x1e/0x1e',
    ' ? up_up_down_down+0x2b/0x40',
    ' ? left_right_left_right+0x16/0x30',
    ' ? b_a_start+0x99/0x99',
    ' exit_vim+0x0/0xffffffffffffffff',
    ' emacs_init+0x1337/0x1337 [evil_mode]',
    ' </TASK>',
    'Modules linked in: ' .. modules,
    '---[ end trace 0000000000000000 ]---',
    'Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000000b',
    '---[ end Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000000b ]---',
  }
  local uptime = vim.uv.uptime()
  local lines = {}
  for i, text in ipairs(body) do
    local stamp = ('[%12.6f] '):format(uptime + i * 0.000011)
    lines[i] = line({ stamp, 'KonamiDim' }, { text, i >= #body - 1 and 'KonamiBright' or 'KonamiText' })
  end
  -- It hangs there for a while.
  return scrolling(lines, 90, 14)
end

local function blank(frames)
  return {
    frames = frames,
    draw = function()
      return {}
    end,
  }
end

local function bios()
  local project = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local cpu = jit and jit.version:match('^%S+ %d+%.%d+') or 'Lua'
  -- Lines and the frame each comes in.
  local steps = {
    { 0, line({ ' Konami Megatrends', 'KonamiBright' }) },
    { 0, line({ (' Neovim BIOS v%s, An Energy Star Ally'):format(version()), 'KonamiText' }) },
    { 0, line({ (' Copyright (C) 1986-%s, Konami Megatrends, Inc.'):format(os.date('%Y')), 'KonamiText' }) },
    { 0, {} },
    { 20, line({ (' Main Processor : %s @ 4.20GHz'):format(cpu), 'KonamiText' }) },
    { 30, 'memory' },
    { 30, {} },
    { 90, line({ ' Detecting Primary Master  ... ', 'KonamiText' }, { 'Ghostty', 'KonamiBright' }) },
    { 105, line({ ' Detecting Primary Slave   ... ', 'KonamiText' }, { project, 'KonamiBright' }) },
    { 120, line({ ' Detecting Secondary Master... None', 'KonamiText' }) },
  }
  return {
    frames = 160,
    draw = function(frame)
      local out = {}
      for _, step in ipairs(steps) do
        if frame < step[1] then
          break
        end
        if step[2] == 'memory' then
          local count = math.min(65536, math.floor((frame - 30) / 50 * 65536))
          table.insert(out, line({ (' Memory Testing : %dK'):format(count), 'KonamiText' }, { count == 65536 and ' OK' or '', 'KonamiBright' }))
        else
          table.insert(out, step[2])
        end
      end
      out[vim.o.lines] = line({ ' Press DEL to run Setup, ↑↑↓↓←→←→BA to panic again', 'KonamiDim' })
      return out
    end,
  }
end

local function grub()
  local entries = {
    'Neovim, with Linux 6.13.0-konami',
    'Neovim, with Linux 6.13.0-konami (recovery mode)',
    'Emacs',
    'Memory test (memtest86+)',
  }
  local width = math.min(70, vim.o.columns - 4)
  local left = (' '):rep(math.max(0, math.floor((vim.o.columns - width - 2) / 2)))
  local function boxed(text, hl)
    text = vim.fn.strcharpart(text, 0, width)
    return line({ left .. '│', 'KonamiText' }, { text .. (' '):rep(width - vim.fn.strdisplaywidth(text)), hl }, { '│', 'KonamiText' })
  end
  return {
    frames = 100,
    draw = function(frame)
      local title = left .. (' '):rep(math.max(0, math.floor(width / 2) - 10)) .. 'GNU GRUB  version 2.12'
      local out = { {}, line({ title, 'KonamiText' }), {}, line({ left .. '┌' .. ('─'):rep(width) .. '┐', 'KonamiText' }) }
      for i, entry in ipairs(entries) do
        table.insert(out, boxed((i == 1 and '*' or ' ') .. entry, i == 1 and 'KonamiSelected' or 'KonamiText'))
      end
      for _ = 1, 6 do
        table.insert(out, boxed('', 'KonamiText'))
      end
      table.insert(out, line({ left .. '└' .. ('─'):rep(width) .. '┘', 'KonamiText' }))
      table.insert(out, {})
      table.insert(out, line({ left .. '     Use the ↑ and ↓ keys to select which entry is highlighted.', 'KonamiText' }))
      local seconds = math.max(0, 3 - math.floor(frame / 30))
      table.insert(out, line({ ('%s     The highlighted entry will be executed automatically in %ds.'):format(left, seconds), 'KonamiText' }))
      return out
    end,
  }
end

local function boot()
  local function ok(text)
    return line({ '[', 'KonamiText' }, { '  OK  ', 'KonamiOk' }, { '] ' .. text, 'KonamiText' })
  end
  local lines = {
    line({ 'Welcome to ', 'KonamiText' }, { ('Neovim %s'):format(version()), 'KonamiBright' }, { '!', 'KonamiText' }),
    {},
    ok('Started Journal Service.'),
    ok(('Mounted %s.'):format(vim.fn.fnamemodify(vim.fn.getcwd(), ':~'))),
  }
  for _, plugin in ipairs(plugins()) do
    local name = plugin:gsub('%.nvim$', ''):gsub('%.lua$', '')
    table.insert(lines, ok(('Started %s.service%s.'):format(name, SERVICES[plugin] and ' - ' .. SERVICES[plugin] or '')))
  end
  for _, server in ipairs({ { 'clangd', 'clangd', 'C/C++' }, { 'basedpyright-langserver', 'basedpyright', 'Python' } }) do
    if vim.fn.executable(server[1]) == 1 then
      table.insert(lines, ok(('Started %s.service - %s Language Server.'):format(server[2], server[3])))
    end
  end
  table.insert(lines, line({ '[', 'KonamiText' }, { 'FAILED', 'KonamiFail' }, { '] Failed to start emacs.service - Emacs.', 'KonamiText' }))
  table.insert(lines, line({ "See 'systemctl status emacs.service' for details.", 'KonamiText' }))
  table.insert(lines, ok('Reached target Modal Editing.'))
  table.insert(lines, ok('Reached target Graphical Interface.'))
  return scrolling(lines, 30, 10)
end

local function login()
  local user = vim.uv.os_get_passwd().username
  return {
    frames = 30 + #user * 5 + 30,
    draw = function(frame)
      local typed = user:sub(1, math.max(0, math.floor((frame - 30) / 5)))
      local cursor = frame % 16 < 8 and '█' or ' '
      return {
        {},
        line({ ('Neovim %s %s tty1'):format(version(), host()), 'KonamiText' }),
        {},
        line({ ('%s login: %s'):format(host(), typed), 'KonamiText' }, { cursor, 'KonamiText' }),
      }
    end,
  }
end

local show -- the one playing

local function stop()
  if not show then
    return
  end
  local ending = show
  show = nil
  ending.timer:stop()
  ending.timer:close()
  pcall(vim.api.nvim_win_close, ending.win, true)
  pcall(vim.api.nvim_buf_delete, ending.buf, { force = true })
end

-- Draws lines of segments into the buffer, each segment in its highlight.
local function render(buf, ns, lines)
  local text, marks = {}, {}
  for r = 1, vim.o.lines do
    local parts, col = {}, 0
    for _, segment in ipairs(lines[r] or {}) do
      table.insert(parts, segment[1])
      table.insert(marks, { r - 1, col, col + #segment[1], segment[2] })
      col = col + #segment[1]
    end
    text[r] = table.concat(parts)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    if mark[3] > mark[2] then
      vim.api.nvim_buf_set_extmark(buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
    end
  end
end

function M.play()
  stop()
  for name, hl in pairs(COLORS) do
    vim.api.nvim_set_hl(0, name, hl)
  end
  math.randomseed(vim.uv.hrtime())
  local scenes = { glitch(capture()), panic(), blank(35), bios(), grub(), blank(20), boot(), login() }

  -- Over the whole screen.
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines,
    style = 'minimal',
    border = 'none',
    focusable = false,
    zindex = 300,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = 'Normal:KonamiText'
  vim.wo[win].wrap = false
  local ns = vim.api.nvim_create_namespace('dotfiles.konami')

  local frame, scene, start = 0, 1, 0
  local timer = assert(vim.uv.new_timer())
  show = { win = win, buf = buf, timer = timer }
  timer:start(0, math.floor(1000 / FPS), vim.schedule_wrap(function()
    if not show or show.timer ~= timer then
      return
    end
    while scenes[scene] and frame - start >= scenes[scene].frames do
      start = start + scenes[scene].frames
      scene = scene + 1
    end
    if not scenes[scene] then
      return stop()
    end
    render(buf, ns, scenes[scene].draw(frame - start))
    frame = frame + 1
  end))
end

-- The start screen, when it is showing.
local function start_screen()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'snacks_dashboard' then
      return win
    end
  end
end

-- The keys last typed on the start screen or in the tree next to it.
local typed_keys = {}

vim.on_key(function(key, typed)
  -- During the show keys do nothing: it plays to the end.
  if show then
    return ''
  end
  local ft = vim.bo.filetype
  local on_start = (ft == 'snacks_dashboard' or ft == 'NvimTree') and vim.api.nvim_get_mode().mode == 'n' and start_screen()
  if not on_start then
    typed_keys = {}
    return
  end
  local name = vim.fn.keytrans(typed ~= '' and typed or key)
  if vim.fn.strcharlen(name) == 1 then
    name = require('config.layout').latin(name):lower()
  end
  table.insert(typed_keys, name)
  if #typed_keys > #SEQUENCE then
    table.remove(typed_keys, 1)
  end
  if table.concat(typed_keys, ' ') == table.concat(SEQUENCE, ' ') then
    typed_keys = {}
    vim.schedule(M.play)
    -- The A goes no further (in the tree it would make a new file).
    return ''
  end
end, vim.api.nvim_create_namespace('dotfiles.konami.keys'))

return M
