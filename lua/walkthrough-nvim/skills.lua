-- walkthrough-nvim.skills — installs this plugin's Claude Code skills
-- (.claude/skills/walkthrough-*) into Claude Code's global skill directory
-- (~/.claude/skills/), where Claude discovers skills for *any* project, not
-- just this repo. Vim-facing (touches vim.uv/vim.fn), like persist/io.lua —
-- not pure/unit-tested, matching this codebase's existing split between
-- pure model/* and vim-facing persist/, server/, ui/ modules.

local M = {}

local uv = vim.uv or vim.loop

--- Where *this plugin* is installed, resolved via the runtimepath -- the
--- same formula every SKILL.md previously duplicated inline for its own
--- `nvim --headless` call. Those skill files now call this function
--- instead (single source of truth), and this module reuses it to find
--- its own .claude/skills/ source directory.
function M.plugin_root()
  return vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/walkthrough-nvim/init.lua', false)[1], ':h:h:h')
end

function M.source_dir()
  return M.plugin_root() .. '/.claude/skills'
end

--- Claude Code's global skill directory -- not per-project, so a skill
--- installed here is available in every repo the user works in, which is
--- the whole point (the repo being walked-through is rarely walkthrough.nvim
--- itself).
function M.target_dir()
  return vim.fn.expand('~/.claude/skills')
end

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'directory'
end

--- Skill names this plugin ships, discovered from its own .claude/skills/
--- directory rather than hardcoded -- a 5th skill folder added later needs
--- no changes here.
function M.discover_skill_names()
  local dir = M.source_dir()
  local names = {}
  for _, name in ipairs(vim.fn.readdir(dir) or {}) do
    if is_dir(dir .. '/' .. name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function normalize(path)
  return (path:gsub('\\', '/')):gsub('/+$', '')
end

--- Read-only: classify every skill's install state under target_dir().
-- @return { [name] = { state, source, target } }
--   state is one of:
--     "missing"    -- nothing at target yet
--     "linked"     -- a symlink/junction already pointing at our source
--     "stale_link" -- a symlink/junction pointing somewhere else (this
--                     plugin was reinstalled at a different path -- safe
--                     to repoint, it's provably ours)
--     "conflict"   -- a real file/dir is there that isn't our link -- do
--                     not touch without force
function M.status()
  local source_dir = M.source_dir()
  local target_dir = M.target_dir()
  local result = {}

  for _, name in ipairs(M.discover_skill_names()) do
    local source = source_dir .. '/' .. name
    local target = target_dir .. '/' .. name
    local entry = { source = source, target = target }

    local lstat = uv.fs_lstat(target)
    if not lstat then
      entry.state = 'missing'
    elseif lstat.type == 'link' then
      local dest = uv.fs_readlink(target)
      if dest and normalize(dest) == normalize(source) then
        entry.state = 'linked'
      else
        entry.state = 'stale_link'
      end
    else
      entry.state = 'conflict'
    end

    result[name] = entry
  end

  return result
end

--- Best-effort directory link: an NTFS junction on Windows (doesn't
--- require admin/Developer Mode, unlike a real symlink), a plain symlink
--- elsewhere. Falls back to a shallow file copy if link creation fails for
--- any reason (permissions, filesystem that doesn't support it, ...).
-- @return outcome "linked" | "copied"
local function link_or_copy(source, target)
  local link_ok = uv.fs_symlink(source, target, { dir = true, junction = true })
  if link_ok then
    return 'linked'
  end

  vim.fn.mkdir(target, 'p')
  for _, file in ipairs(vim.fn.readdir(source) or {}) do
    local lines = vim.fn.readfile(source .. '/' .. file, 'b')
    vim.fn.writefile(lines, target .. '/' .. file, 'b')
  end
  return 'copied'
end

--- Fix up every skill's install state: create missing links, repoint stale
--- ones (safe -- a stale link is provably ours), and only touch a real
--- conflicting path when opts.force is true.
-- @param opts { force: boolean }
-- @return { [name] = { state, outcome, source, target } } -- state is the
--   pre-fix classification from status(), outcome is what link_skills did
--   about it ("up_to_date" | "linked" | "copied" | "relinked" |
--   "skipped_conflict" | "removed_conflict_then_linked" | "removed_conflict_then_copied")
function M.link_skills(opts)
  opts = opts or {}
  vim.fn.mkdir(M.target_dir(), 'p')

  local result = M.status()
  for name, entry in pairs(result) do
    if entry.state == 'linked' then
      entry.outcome = 'up_to_date'
    elseif entry.state == 'missing' then
      entry.outcome = link_or_copy(entry.source, entry.target)
    elseif entry.state == 'stale_link' then
      uv.fs_unlink(entry.target)
      entry.outcome = 'relinked_' .. link_or_copy(entry.source, entry.target)
    elseif entry.state == 'conflict' then
      if opts.force then
        vim.fn.delete(entry.target, 'rf')
        entry.outcome = 'removed_conflict_then_' .. link_or_copy(entry.source, entry.target)
      else
        entry.outcome = 'skipped_conflict'
      end
    end
  end

  return result
end

return M
