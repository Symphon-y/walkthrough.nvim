-- walkthrough-nvim.persist.paths — where a walkthrough's files live.
--
-- Layout:
--   <stdpath('data')>/walkthrough-nvim/<repo-hash>/
--     repo.json                        -- { repo_root = "..." } human-resolvable hash->path
--     <walkthrough_id>/
--       manifest.json
--       revisions/<revision_id>.json
--
-- repo-hash = sha256(repo_root)[:16], with repo_root normalized to forward
-- slashes FIRST. This file is the one source of truth for that hashing —
-- both the plugin and the `walkthrough-explore` Claude Code skill (via a
-- headless `nvim --headless -c "lua print(...)"` call into this module)
-- resolve paths through it, so they can never silently compute different
-- hashes for the same repo.

local M = {}

local schema = require('walkthrough-nvim.model.schema')

--- Normalize a repo root for hashing/display: backslash -> forward slash,
--- no trailing slash. Must be applied identically everywhere a repo_root
--- is hashed (Windows path separators would otherwise change the hash).
function M.normalize_root(root)
  assert(type(root) == 'string' and root ~= '', 'root must be a non-empty string')
  local s = root:gsub('\\', '/')
  s = s:gsub('/+$', '')
  return s
end

--- The stable 16-hex-char identity for a repo root.
function M.repo_hash(root)
  return vim.fn.sha256(M.normalize_root(root)):sub(1, 16)
end

--- Base directory for all walkthrough-nvim state. Defaults to
--- stdpath('data'); overridable via setup({ data_dir = ... }), which is
--- how tests point this at a scratch directory instead of real user data.
function M.data_root()
  local override = require('walkthrough-nvim.config').options.data_dir
  return (override or vim.fn.stdpath('data')) .. '/walkthrough-nvim'
end

function M.repo_dir(root)
  return M.data_root() .. '/' .. M.repo_hash(root)
end

--- Path to the small { repo_root = ... } file that makes a repo-hash
--- directory human-resolvable back to a real path.
function M.repo_identity_path(root)
  return M.repo_dir(root) .. '/repo.json'
end

local function valid_slug(s)
  return type(s) == 'string' and s:match('^[%w%-_]+$') ~= nil
end

--- A walkthrough_id or revision_id used as a path component must be a
--- plain slug — rejects anything that could path-traverse (e.g. "../x").
function M.assert_valid_slug(s, what)
  if not valid_slug(s) then
    error(('walkthrough: invalid %s %q (expected [%%w%%-_]+)'):format(what or 'id', tostring(s)))
  end
end

function M.walkthrough_dir(root, walkthrough_id)
  M.assert_valid_slug(walkthrough_id, 'walkthrough_id')
  return M.repo_dir(root) .. '/' .. walkthrough_id
end

function M.manifest_path(root, walkthrough_id)
  return M.walkthrough_dir(root, walkthrough_id) .. '/manifest.json'
end

function M.revisions_dir(root, walkthrough_id)
  return M.walkthrough_dir(root, walkthrough_id) .. '/revisions'
end

function M.revision_path(root, walkthrough_id, revision_id)
  M.assert_valid_slug(revision_id, 'revision_id')
  return M.revisions_dir(root, walkthrough_id) .. '/' .. revision_id .. '.json'
end

local PREFIX_BY_PHASE = {
  [schema.PHASE.EXPLORATION] = 'expl',
  [schema.PHASE.IMPLEMENTATION] = 'impl',
  [schema.PHASE.PROPOSAL] = 'prop',
}

--- Compute the next revision id for `phase` given a manifest table (or
--- nil, for a brand-new walkthrough). Pure — takes the manifest as data
--- rather than reading it, so it's testable without touching disk; see
--- io.lua's next_revision_path() for the version that actually reads one.
function M.next_revision_id(manifest, phase)
  local prefix = PREFIX_BY_PHASE[phase]
  assert(prefix, 'invalid phase: ' .. tostring(phase))

  local max_n = 0
  for _, rev in ipairs((manifest and manifest.revisions) or {}) do
    if rev.phase == phase then
      local n = tonumber(tostring(rev.id):match('%-(%d+)$'))
      if n and n > max_n then
        max_n = n
      end
    end
  end
  return string.format('%s-%03d', prefix, max_n + 1)
end

return M
