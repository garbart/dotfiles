-- Copy Git Link (right-click menu, see menu.lua): the web page of the
-- current line, or the selected lines, on the host of the origin remote:
-- GitHub, GitLab, Bitbucket, Gitea / Forgejo / Codeberg, Azure DevOps; any
-- other host gets GitLab's links, as self-hosted ones mostly are GitLab.
-- The link is to the commit, so it keeps pointing at the same lines, when
-- it is pushed; otherwise to the branch, if the remote has it.

local M = {}

local function git(dir, args)
  local result = vim.system(vim.list_extend({ 'git', '-C', dir }, args), { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or nil
end

-- The repository of a file, and its remote (origin, else the first one).
local function repository(file)
  local root = git(vim.fs.dirname(file), { 'rev-parse', '--show-toplevel' })
  if not root then
    return
  end
  local remotes = vim.split(git(root, { 'remote' }) or '', '\n', { trimempty = true })
  local remote = vim.tbl_contains(remotes, 'origin') and 'origin' or remotes[1]
  return root, remote
end

-- Whether the current file has a repository with a remote to link to.
function M.available()
  local file = vim.api.nvim_buf_get_name(0)
  return vim.bo.buftype == '' and file ~= '' and select(2, repository(file)) ~= nil
end

-- The web address of a remote's repository: from git@host:path, ssh://,
-- git:// and http(s):// URLs. An ssh host may be an alias of
-- ~/.ssh/config: its HostName is the real one.
local function web(url)
  local scheme, rest = url:match('^(%a[%w+.-]*)://(.+)$')
  local host, path
  if scheme then
    host, path = rest:match('^([^/]+)/(.+)$')
  else
    scheme = 'ssh'
    host, path = url:match('^([^:/]+):(.+)$')
  end
  if not host then
    return
  end
  host = host:gsub('^.*@', '')
  path = path:gsub('%.git/?$', ''):gsub('/$', '')
  if scheme ~= 'http' and scheme ~= 'https' then
    host = host:gsub(':%d+$', '')
    local ok, ssh = pcall(vim.system, { 'ssh', '-G', host }, { text = true })
    host = ok and (ssh:wait().stdout or ''):match('%f[^\n%z]hostname (%S+)') or host
    scheme = 'https'
  end
  -- Azure's ssh address names the repository otherwise.
  if host == 'ssh.dev.azure.com' then
    host = 'dev.azure.com'
    path = path:gsub('^v3/([^/]+)/([^/]+)/', '%1/%2/_git/')
  end
  return scheme .. '://' .. host, host, path
end

local function encode(path)
  return (path:gsub('[^%w%-._~/]', function(char)
    return ('%%%02X'):format(char:byte())
  end))
end

-- The link to lines first..last of a file (its path in the repository) at
-- ref, a commit (sha) or a branch.
local function link(base, host, path, ref, sha, file, first, last)
  local repo = base .. '/' .. path
  file = encode(file)
  local more = last > first
  if host:find('github') then
    return ('%s/blob/%s/%s#L%d%s'):format(repo, ref, file, first, more and '-L' .. last or '')
  elseif host:find('bitbucket') then
    return ('%s/src/%s/%s#lines-%d%s'):format(repo, ref, file, first, more and ':' .. last or '')
  elseif host:find('codeberg') or host:find('gitea') or host:find('forgejo') then
    local kind = sha and 'commit' or 'branch'
    return ('%s/src/%s/%s/%s#L%d%s'):format(repo, kind, ref, file, first, more and '-L' .. last or '')
  elseif host:find('dev%.azure%.com$') or host:find('visualstudio%.com$') then
    return ('%s?path=/%s&version=%s%s&line=%d&lineEnd=%d&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents'):format(
      repo,
      file,
      sha and 'GC' or 'GB',
      ref,
      first,
      last + 1
    )
  end
  return ('%s/-/blob/%s/%s#L%d%s'):format(repo, ref, file, first, more and '-' .. last or '')
end

-- Copies the link to the selected lines, or the current one.
function M.copy()
  local file = vim.api.nvim_buf_get_name(0)
  local root, remote = repository(file)
  if not remote then
    return vim.notify('No git remote to link to', vim.log.levels.WARN)
  end
  local base, host, path = web(git(root, { 'remote', 'get-url', remote }) or '')
  if not base then
    return vim.notify('Unknown address of remote ' .. remote, vim.log.levels.WARN)
  end
  local first, last = vim.fn.line('v'), vim.fn.line('.')
  if not vim.api.nvim_get_mode().mode:find('^[vVsS\22\19]') then
    first = last
  end
  first, last = math.min(first, last), math.max(first, last)

  local ref = git(root, { 'rev-parse', 'HEAD' })
  local sha = ref ~= nil
  local pushed = ref and (git(root, { 'branch', '-r', '--contains', ref }) or '') ~= ''
  if not pushed then
    local branch = git(root, { 'symbolic-ref', '--short', '-q', 'HEAD' })
    if branch and git(root, { 'rev-parse', '--verify', '-q', ('refs/remotes/%s/%s'):format(remote, branch) }) then
      ref, sha = branch, false
      vim.notify('The commit is not pushed: the link is to branch ' .. branch, vim.log.levels.WARN)
    else
      vim.notify('The commit is not pushed: the link may not open yet', vim.log.levels.WARN)
    end
  end

  local url = link(base, host, path, ref or 'HEAD', sha, vim.fs.relpath(root, file) or file, first, last)
  vim.fn.setreg('+', url)
  vim.notify('Copied ' .. url)
end

return M
