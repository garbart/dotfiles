-- C and C++ by clangd (the language server VSCode's clangd extension runs
-- too): code colored by meaning (types, macros, members, parameters, as in
-- CLion) over tree-sitter's colors, errors and warnings underlined,
-- completion (see completion.lua), go to definition (F12 or Ctrl+click),
-- references (Shift+F12), the symbols of the file (Cmd+Shift+O), back and
-- forward (Ctrl+- / Ctrl+Shift+-). Cmd+S formats the file by the project's
-- .clang-format before saving; saving by itself (autosave.lua) doesn't
-- format.
--
-- clangd reads the compile commands CMake writes when configuring (with
-- CMAKE_EXPORT_COMPILE_COMMANDS), from whichever build folder was configured
-- last: the newest compile_commands.json in the project, wherever the build
-- went (build/, cmake-build-debug/, .build/release/, out/build/x64/).
-- This beats a CompilationDatabase in the project's .clangd. It asks the
-- compiler they use (e.g. Homebrew's g++-15) for its standard library
-- headers.

local M = {}

-- Folders not searched for compile commands: git's, CMake's own inside a
-- build folder, and git submodules (projects of their own, whose builds
-- don't describe this one).
local SKIP = { ['.git'] = true, node_modules = true, CMakeFiles = true, _deps = true }

local function submodules(root)
  local paths = {}
  local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(root, '.gitmodules'))
  for _, line in ipairs(ok and lines or {}) do
    local path = line:match('^%s*path%s*=%s*(.-)%s*$')
    if path then
      paths[path] = true
    end
  end
  return paths
end

-- The newest compile_commands.json in the project (the root and folders up
-- to three levels down), and when it was written; nil if there is none.
local function newest_compile_commands(root)
  local skipped = submodules(root)
  local newest, newest_time
  for name, type in vim.fs.dir(root, {
    depth = 4,
    skip = function(dir)
      return not (SKIP[vim.fs.basename(dir)] or skipped[dir])
    end,
  }) do
    if type == 'file' and vim.fs.basename(name) == 'compile_commands.json' then
      local file = vim.fs.joinpath(root, name)
      local stat = vim.uv.fs_stat(file)
      local time = stat and stat.mtime.sec + stat.mtime.nsec / 1e9
      if time and (not newest_time or time > newest_time) then
        newest, newest_time = file, time
      end
    end
  end
  return newest, newest_time
end

vim.lsp.config('clangd', {
  cmd = function(dispatchers, config)
    local cmd = {
      'clangd',
      '--background-index',
      '--header-insertion=never',
      -- The compilers clangd may ask: the system's, Homebrew's and toolsets
      -- in /opt (e.g. Rocky's gcc-toolset).
      '--query-driver=/usr/bin/*,/usr/local/bin/*,/opt/**/bin/*',
    }
    local file = config.root_dir and newest_compile_commands(config.root_dir)
    if file then
      table.insert(cmd, '--compile-commands-dir=' .. vim.fs.dirname(file))
    end
    return vim.lsp.rpc.start(cmd, dispatchers, { cwd = config.root_dir })
  end,
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
  -- The project open in nvim; files elsewhere get the nearest one.
  root_dir = function(buf, on_dir)
    local path, cwd = vim.api.nvim_buf_get_name(buf), vim.fn.getcwd()
    on_dir(vim.fs.relpath(cwd, path) and cwd or vim.fs.root(buf, { '.clangd', 'compile_commands.json', '.git' }))
  end,
})

if vim.fn.executable('clangd') == 1 then
  vim.lsp.enable('clangd')
end

-- clangd doesn't notice compile commands written after it started, as when
-- the project is configured in the shell next to nvim. So when nvim gets the
-- focus back, clangd restarts if a build folder was configured since: with
-- the newest compile commands, which may now be another build's.
local function compile_commands_stamp(root)
  local file, time = newest_compile_commands(root)
  return file and file .. '@' .. time or '-'
end

local stamps = {}

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == 'clangd' and client.root_dir and not stamps[client.id] then
      stamps[client.id] = compile_commands_stamp(client.root_dir)
    end
  end,
})

vim.api.nvim_create_autocmd('FocusGained', {
  callback = function()
    for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
      if client.root_dir and stamps[client.id] and stamps[client.id] ~= compile_commands_stamp(client.root_dir) then
        vim.cmd('lsp restart clangd')
        return
      end
    end
  end,
})

-- Errors and warnings are underlined as they come (also while typing, which
-- is most of the time, see modeless.lua); the message of the cursor's line
-- shows at its end. No marks next to the line numbers: that column is for
-- git.
vim.diagnostic.config({
  underline = true,
  virtual_text = { current_line = true },
  signs = false,
  severity_sort = true,
  update_in_insert = true,
})

-- Formats the current file by its language server, if it has one that can.
function M.format()
  if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/formatting' }) > 0 then
    vim.lsp.buf.format({ async = false, timeout_ms = 3000 })
  end
end

-- Keys ------------------------------------------------------------------------

local function map(modes, keys, fn, desc)
  for _, key in ipairs(keys) do
    vim.keymap.set(modes, key, fn, { desc = desc })
  end
end

-- Opens a picker of places; after the jump the file is ready for typing
-- again (see modeless.lua), also when the picker jumped straight to the only
-- place.
local function pick(source)
  -- From normal mode, so the picker jumps right away (from insert mode it
  -- defers the jump, past the check below).
  if vim.api.nvim_get_mode().mode:sub(1, 1) == 'i' then
    -- Leaving insert mode moves the cursor left; the place asked about is
    -- where it was.
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.cmd.stopinsert()
    vim.schedule(function()
      vim.api.nvim_win_set_cursor(0, cursor)
      pick(source)
    end)
    return
  end
  Snacks.picker[source]({
    on_close = function()
      vim.schedule(function()
        if vim.api.nvim_get_mode().mode == 'n' and vim.bo.buftype == '' and vim.bo.modifiable then
          vim.cmd.startinsert()
        end
      end)
    end,
  })
end

map({ 'n', 'i' }, { '<F12>' }, function()
  pick('lsp_definitions')
end, 'Go to definition')
map({ 'n', 'i' }, { '<S-F12>', '<F24>' }, function()
  pick('lsp_references')
end, 'Go to references')
map({ 'n', 'i' }, { '<D-O>' }, function()
  pick('lsp_symbols')
end, 'Go to symbol in file')
-- Ctrl+click: the definition of what was clicked.
map({ 'n', 'i' }, { '<C-LeftMouse>' }, function()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= 0 and pos.line > 0 then
    vim.api.nvim_set_current_win(pos.winid)
    vim.api.nvim_win_set_cursor(pos.winid, { pos.line, math.max(pos.column - 1, 0) })
    pick('lsp_definitions')
  end
end, 'Go to definition')
-- Back and forward through the places jumped from.
map({ 'n', 'i' }, { '<C-->' }, '<Cmd>execute "normal! \\<C-o>"<CR>', 'Go back')
map({ 'n', 'i' }, { '<C-_>', '<C-S-->' }, '<Cmd>execute "normal! \\<C-i>"<CR>', 'Go forward')

return M
