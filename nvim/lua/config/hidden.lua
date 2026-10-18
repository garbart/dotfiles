-- Files hidden from the file tree, per project. Right click > Hide hides
-- the selected ones; the eye button in the tree header shows them (dimmed) and hides them
-- again. The list is kept in the project, in .nvim/settings.json, in the
-- format of VSCode's files.exclude: glob patterns relative to the project
-- root, set to true. Hiding a folder hides everything in it.
--
--   { "files.exclude": { "build": true, "**/*.o": true } }

local M = {}

-- Whether hidden files are shown, until nvim quits.
M.showing = false

local cache = {}

function M.file(root)
  return vim.fs.joinpath(root or vim.fn.getcwd(), '.nvim', 'settings.json')
end

-- The settings of the current project. The tree asks for every file it
-- draws, so the file is checked at most once per event loop iteration and
-- read again only when it changed.
local function settings()
  local root, now = vim.fn.getcwd(), vim.uv.now()
  if cache.root == root and cache.checked == now then
    return cache
  end
  local stat = vim.uv.fs_stat(M.file(root))
  local stamp = stat and ('%d.%d.%d'):format(stat.mtime.sec, stat.mtime.nsec, stat.size)
  if cache.root == root and cache.stamp == stamp then
    cache.checked = now
    return cache
  end

  cache = { root = root, checked = now, stamp = stamp, data = vim.empty_dict(), globs = {}, count = 0 }
  if stat then
    local text = table.concat(vim.fn.readfile(M.file(root)), '\n')
    local ok, data = pcall(vim.json.decode, text, { skip_comments = true })
    if ok and type(data) == 'table' then
      cache.data = data
    else
      cache.broken = true
    end
  end
  local exclude = cache.data['files.exclude']
  cache.exclude = type(exclude) == 'table' and exclude or {}
  for pattern, on in pairs(cache.exclude) do
    if on == true then
      cache.count = cache.count + 1
      local ok, glob = pcall(vim.glob.to_lpeg, pattern)
      if ok then
        table.insert(cache.globs, glob)
      end
    end
  end
  return cache
end

local function matches(s, rel)
  if s.exclude[rel] == true then
    return true
  end
  for _, glob in ipairs(s.globs) do
    if glob:match(rel) then
      return true
    end
  end
  return false
end

-- Whether a file (absolute path) is hidden: by itself or by a folder above.
function M.is_hidden(path)
  local s = settings()
  if s.count == 0 then
    return false
  end
  local rel = vim.fs.relpath(s.root, path)
  while rel and rel ~= '.' do
    if matches(s, rel) then
      return true
    end
    rel = vim.fs.dirname(rel)
  end
  return false
end

-- For the right-click menu: 'listed' when the file itself is in the list
-- (can be unhidden), 'hidden' when hidden otherwise (by a pattern or a
-- folder above), 'visible', or nil outside the project.
function M.state(path)
  local s = settings()
  local rel = vim.fs.relpath(s.root, path)
  if not rel or rel == '.' then
    return nil
  end
  if s.exclude[rel] == true then
    return 'listed'
  end
  return M.is_hidden(path) and 'hidden' or 'visible'
end

-- How many entries hide something.
function M.count()
  return settings().count
end

local function redraw()
  require('nvim-tree.api').tree.reload()
  vim.cmd('redrawstatus!')
end

-- Changes the list for a path, or several, and writes it back, keeping any
-- other settings.
local function update(paths, value)
  local s = settings()
  if s.broken then
    vim.notify(M.file(s.root) .. ' is not valid JSON', vim.log.levels.ERROR)
    return
  end
  local exclude = s.exclude
  for _, path in ipairs(type(paths) == 'table' and paths or { paths }) do
    local rel = vim.fs.relpath(s.root, path)
    if rel and rel ~= '.' then
      exclude[rel] = value
    end
  end
  s.data['files.exclude'] = next(exclude) and exclude or nil
  local file = M.file(s.root)
  if next(s.data) then
    vim.fn.mkdir(vim.fs.dirname(file), 'p')
    local json = vim.json.encode(s.data, { indent = '  ', sort_keys = true })
    vim.fn.writefile(vim.split(json, '\n'), file)
  else
    -- Nothing left: no empty file or .nvim folder in the project.
    os.remove(file)
    vim.uv.fs_rmdir(vim.fs.dirname(file))
  end

  cache = {}
  if M.count() == 0 then
    M.showing = false
  end
  redraw()
end

-- Hides a path, or several.
function M.hide(paths)
  update(paths, true)
end

function M.unhide(paths)
  update(paths, nil)
end

function M.toggle()
  M.showing = not M.showing
  redraw()
end

-- Edits to the file made by hand show up in the tree on save.
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*/.nvim/settings.json',
  callback = function()
    cache = {}
    redraw()
  end,
})

return M
