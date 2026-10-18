-- Keys work in the Russian layout too. Cmd+key shortcuts are bound to the
-- physical keys in Ghostty (see config.ghostty); this is for the keys of
-- normal mode. Vim's own commands go through 'langmap': outside typing, a
-- Russian letter stands for the Latin one on the same key (в for d, к for
-- r...). 'langmap' doesn't reach mappings of letters longer than a byte, so
-- each mapping of Latin keys (the tree's d, r, a..., the start screen's, the
-- leader ones) gets a twin of the Russian ones. Typed text, also over a
-- selection, stays as typed.

local M = {}

local en = [[qwertyuiop[]asdfghjkl;'zxcvbnm,.QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>]]
local ru = vim.fn.split('йцукенгшщзхъфывапролджэячсмитьбюЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ', '\\zs')

local russian, latin = {}, {} ---@type table<string, string>, table<string, string>
local langmap = {} ---@type string[]
for i = 1, #en do
  local key = en:sub(i, i)
  russian[key], latin[ru[i]] = ru[i], key
  table.insert(langmap, ru[i] .. key:gsub('[;,"\\]', '\\%0'))
end
vim.o.langmap = table.concat(langmap, ',')

-- The Latin key of a character typed in the Russian layout (others as they
-- are), for keys read by hand (see menu.lua).
function M.latin(char)
  return latin[char] or char
end

-- The keys of a mapping typed in the Russian layout, if any differ: its
-- letters, and Cmd+letter (<D-x>; Cmd+Shift+С reaches nvim as <D-S-с>, and
-- <D-С> is there too to be sure). Other <...> keys stay as they are.
local function in_russian(lhs)
  local plain, shifted, changed, i = {}, {}, false, 1
  while i <= #lhs do
    local special = lhs:match('^<[^<>]+>', i)
    local key = special and special:match('^<D%-(.)>$') or not special and lhs:sub(i, i)
    local ru = key and russian[key] or nil
    changed = changed or ru ~= nil
    if special then
      table.insert(plain, ru and '<D-' .. ru .. '>' or special)
      table.insert(shifted, ru and key:match('%u') and '<D-S-' .. russian[key:lower()] .. '>' or plain[#plain])
    else
      table.insert(plain, ru or key)
      table.insert(shifted, ru or key)
    end
    i = i + (special and #special or 1)
  end
  plain, shifted = table.concat(plain), table.concat(shifted)
  return changed and (plain == shifted and { plain } or { plain, shifted }) or {}
end

-- Gives the normal and visual mode mappings of buf (nil: the global ones)
-- their Russian twins.
function M.twin(buf)
  for _, mode in ipairs({ 'n', 'x' }) do
    local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
    local taken = {}
    for _, map in ipairs(maps) do
      taken[map.lhs] = true
    end
    for _, map in ipairs(maps) do
      local rhs = map.callback or map.rhs or ''
      local twins = map.lhs:find('<Plug>', 1, true) and {} or in_russian(map.lhs)
      for _, lhs in ipairs(type(rhs) == 'string' and rhs:find('<SID>', 1, true) and {} or twins) do
        if not taken[lhs] then
          taken[lhs] = true
          vim.keymap.set(mode, lhs, rhs, {
            buffer = buf,
            remap = map.noremap == 0,
            expr = map.expr == 1,
            replace_keycodes = map.expr == 1 and map.replace_keycodes == 1 or nil,
            silent = map.silent == 1,
            nowait = map.nowait == 1,
            desc = map.desc,
          })
        end
      end
    end
  end
end

local group = vim.api.nvim_create_augroup('dotfiles.layout', {})

-- Once all is set up; a buffer's own once its file type is (plugins map
-- keys right after, hence the delay), the start screen's each time it's
-- drawn (it maps its keys then).
vim.api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    M.twin()
  end,
})
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  callback = function(args)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) then
        M.twin(args.buf)
      end
    end)
  end,
})
vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'SnacksDashboardUpdatePost',
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'snacks_dashboard' then
        M.twin(buf)
      end
    end
  end,
})

return M
