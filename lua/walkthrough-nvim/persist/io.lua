-- walkthrough-nvim.persist.io — actual reads/writes for walkthrough state.
-- Owns the write-tmp-then-rename atomicity so a crash mid-write can never
-- leave a half-written revision file, and the manifest/current-revision
-- bookkeeping that goes with writing a new revision.

local M = {}

local paths = require('walkthrough-nvim.persist.paths')
local schema = require('walkthrough-nvim.model.schema')

local uv = vim.uv or vim.loop

local function ensure_dir(dir)
  vim.fn.mkdir(dir, 'p')
end

--- Read and JSON-decode a file.
-- @return ok boolean
-- @return data table|nil on success, error message string on failure
function M.read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return false, 'no such file: ' .. path
  end
  local lines = vim.fn.readfile(path)
  local ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok then
    return false, 'invalid JSON in ' .. path .. ': ' .. tostring(data)
  end
  return true, data
end

--- JSON-encode and write a file atomically: write to a sibling tmp file,
--- then rename over the target. `vim.uv.fs_rename` (libuv) is used rather
--- than plain `os.rename` because os.rename does not overwrite an
--- existing file on Windows -- libuv normalizes that cross-platform.
-- @return ok boolean
-- @return err string|nil
function M.write_json_atomic(path, data)
  ensure_dir(vim.fn.fnamemodify(path, ':h'))
  local tmp = path .. '.tmp-' .. tostring(uv.os_getpid()) .. '-' .. tostring(math.random(0, 0xffffff))

  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return false, 'could not encode JSON: ' .. tostring(encoded)
  end

  local write_ok = pcall(vim.fn.writefile, { encoded }, tmp, 'b')
  if not write_ok then
    return false, 'could not write ' .. tmp
  end

  local rename_ok, rename_err = uv.fs_rename(tmp, path)
  if not rename_ok then
    pcall(os.remove, tmp)
    return false, 'could not rename into place: ' .. tostring(rename_err)
  end
  return true, nil
end

--- Ensure <repo-hash>/repo.json exists so the hash directory stays
--- human-resolvable back to a real path.
function M.write_repo_identity(root)
  local path = paths.repo_identity_path(root)
  if vim.fn.filereadable(path) == 1 then
    return true, nil
  end
  return M.write_json_atomic(path, { repo_root = paths.normalize_root(root) })
end

local function empty_manifest(walkthrough_id)
  return {
    schema_version = schema.SCHEMA_VERSION,
    walkthrough_id = walkthrough_id,
    title = walkthrough_id,
    revisions = {},
    current = {},
  }
end

--- Read a walkthrough's manifest, returning a fresh empty one if it
--- doesn't exist yet (a brand-new walkthrough, not an error).
function M.read_manifest(root, walkthrough_id)
  paths.assert_valid_slug(walkthrough_id, 'walkthrough_id')
  local path = paths.manifest_path(root, walkthrough_id)
  if vim.fn.filereadable(path) ~= 1 then
    return empty_manifest(walkthrough_id)
  end
  local ok, data = M.read_json(path)
  if not ok then
    error('walkthrough: ' .. data)
  end
  return data
end

function M.write_manifest(root, walkthrough_id, manifest)
  return M.write_json_atomic(paths.manifest_path(root, walkthrough_id), manifest)
end

--- Read one revision file.
function M.read_revision(root, walkthrough_id, revision_id)
  return M.read_json(paths.revision_path(root, walkthrough_id, revision_id))
end

--- The single file path Claude should write its next revision to:
--- resolves the manifest, mints the next revision id for `phase` via
--- paths.next_revision_id, and returns the full path (creating the
--- revisions/ directory if this is the walkthrough's first revision).
--- This is the one function the `walkthrough-explore`/`-reconcile`/
--- `-asbuilt` skills call (via `nvim --headless -c "lua print(...)"`) so
--- path/hash/numbering logic never drifts between the plugin and the
--- skill prompt.
function M.next_revision_path(root, walkthrough_id, phase)
  local manifest = M.read_manifest(root, walkthrough_id)
  local revision_id = paths.next_revision_id(manifest, phase)
  ensure_dir(paths.revisions_dir(root, walkthrough_id))
  return paths.revision_path(root, walkthrough_id, revision_id)
end

--- Validate and write a new revision: writes the revision file, appends
--- it to the manifest, and advances manifest.current[phase] to it. The
--- model's own revision_id/phase are trusted as already correctly minted
--- (by the skill, via next_revision_id) -- this function does not mint
--- ids itself, only persists.
-- @return ok boolean
-- @return err string|nil (schema errors joined, or an I/O error)
function M.write_revision(root, model)
  local valid, errors = schema.validate(model)
  if not valid then
    return false, table.concat(errors, '; ')
  end

  M.write_repo_identity(root)

  local manifest = M.read_manifest(root, model.walkthrough_id)
  local write_ok, write_err = M.write_json_atomic(paths.revision_path(root, model.walkthrough_id, model.revision_id), model)
  if not write_ok then
    return false, write_err
  end

  manifest.revisions = manifest.revisions or {}
  local already_listed = false
  for _, rev in ipairs(manifest.revisions) do
    if rev.id == model.revision_id then
      already_listed = true
      rev.status = model.status
    end
  end
  if not already_listed then
    table.insert(manifest.revisions, {
      id = model.revision_id,
      phase = model.phase,
      status = model.status,
      created_by = model.created_by,
      parent = model.parent_revision,
    })
  end

  manifest.current = manifest.current or {}
  manifest.current[model.phase] = model.revision_id

  return M.write_manifest(root, model.walkthrough_id, manifest)
end

--- List every walkthrough_id with saved state under this repo.
function M.list_walkthroughs(root)
  local names = {}
  for _, path in ipairs(vim.fn.glob(paths.repo_dir(root) .. '/*/manifest.json', false, true)) do
    names[#names + 1] = vim.fn.fnamemodify(path, ':h:t')
  end
  table.sort(names)
  return names
end

return M
