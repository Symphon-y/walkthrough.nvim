local M = {}

local config = require('walkthrough-nvim.config')

function M.setup(opts)
  config.setup(opts)
end

--- Read a walkthrough revision JSON file and validate it against the
--- schema, reporting via vim.notify. This is the model layer's only
--- Neovim-facing surface until persistence/server/UI land (Phase 1+).
function M.validate(path)
  local schema = require('walkthrough-nvim.model.schema')

  local read_ok, lines = pcall(vim.fn.readfile, path)
  if not read_ok then
    vim.notify('walkthrough: could not read ' .. path, vim.log.levels.ERROR)
    return
  end

  local decode_ok, model = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decode_ok then
    vim.notify('walkthrough: ' .. path .. ' is not valid JSON: ' .. tostring(model), vim.log.levels.ERROR)
    return
  end

  local valid, errors = schema.validate(model)
  if valid then
    vim.notify('walkthrough: ' .. path .. ' is valid', vim.log.levels.INFO)
  else
    vim.notify('walkthrough: ' .. path .. ' failed validation:\n' .. table.concat(errors, '\n'), vim.log.levels.ERROR)
  end
end

local function no_id_notice(root, usage)
  local io_mod = require('walkthrough-nvim.persist.io')
  local names = io_mod.list_walkthroughs(root)
  if #names == 0 then
    vim.notify('walkthrough: no walkthroughs found for this repo yet', vim.log.levels.WARN)
  else
    vim.notify('walkthrough: usage ' .. usage .. '\navailable: ' .. table.concat(names, ', '), vim.log.levels.WARN)
  end
end

--- Load `revision_id` of `walkthrough_id`: starts the local server, points
--- a browser at its component/architecture diagram, and wires
--- jump-to-source back into this Neovim instance. Shared by M.open
--- (resolves the current exploration revision), M.load (an explicit
--- revision, e.g. from :WalkthroughHistory), and M.diff (opens the
--- implementation revision with a before/after diff attached).
local function open_revision(root, walkthrough_id, revision_id, diff)
  local io_mod = require('walkthrough-nvim.persist.io')
  local state = require('walkthrough-nvim.ui.state')

  local read_ok, model = io_mod.read_revision(root, walkthrough_id, revision_id)
  if not read_ok then
    vim.notify('walkthrough: ' .. tostring(model), vim.log.levels.ERROR)
    return
  end

  state.clear() -- stop any previously open session's server first

  state.new(root, walkthrough_id, model, diff)
  local server = require('walkthrough-nvim.server.server').start({
    engine = require('walkthrough-nvim.server.bridge'),
  })
  state.session.server = server

  require('walkthrough-nvim.server.browser').open(server:url('/'))
  vim.notify('walkthrough: opened ' .. walkthrough_id .. ' (' .. revision_id .. ')', vim.log.levels.INFO)
end

--- Open a walkthrough's current exploration revision.
function M.open(walkthrough_id)
  local root = require('walkthrough-nvim.persist.root').find()

  if not walkthrough_id or walkthrough_id == '' then
    no_id_notice(root, ':WalkthroughOpen {id}')
    return
  end

  local io_mod = require('walkthrough-nvim.persist.io')
  local ok, manifest = pcall(io_mod.read_manifest, root, walkthrough_id)
  if not ok then
    vim.notify('walkthrough: ' .. tostring(manifest), vim.log.levels.ERROR)
    return
  end

  local revision_id = manifest.current and manifest.current.exploration
  if not revision_id then
    vim.notify('walkthrough: no exploration revision for "' .. walkthrough_id .. '" yet -- run the walkthrough-explore skill first', vim.log.levels.WARN)
    return
  end

  open_revision(root, walkthrough_id, revision_id)
end

--- Open a specific revision directly (bypasses manifest.current).
function M.load(walkthrough_id, revision_id)
  if not walkthrough_id or walkthrough_id == '' or not revision_id or revision_id == '' then
    vim.notify('walkthrough: usage :WalkthroughLoad {walkthrough_id} {revision_id}', vim.log.levels.ERROR)
    return
  end
  local root = require('walkthrough-nvim.persist.root').find()
  open_revision(root, walkthrough_id, revision_id)
end

--- Pick a revision from a walkthrough's history and open it.
function M.history(walkthrough_id)
  local root = require('walkthrough-nvim.persist.root').find()

  if not walkthrough_id or walkthrough_id == '' then
    no_id_notice(root, ':WalkthroughHistory {id}')
    return
  end

  local io_mod = require('walkthrough-nvim.persist.io')
  local ok, manifest = pcall(io_mod.read_manifest, root, walkthrough_id)
  if not ok then
    vim.notify('walkthrough: ' .. tostring(manifest), vim.log.levels.ERROR)
    return
  end

  if not manifest.revisions or #manifest.revisions == 0 then
    local paths = require('walkthrough-nvim.persist.paths')
    vim.notify(
      'walkthrough: no revisions for "'
        .. walkthrough_id
        .. '" under root '
        .. root
        .. ' (repo dir: '
        .. paths.repo_dir(root)
        .. ') -- if you seeded this elsewhere, cwd/root resolved differently here',
      vim.log.levels.WARN
    )
    return
  end

  vim.ui.select(manifest.revisions, {
    prompt = 'walkthrough history: ' .. walkthrough_id,
    format_item = function(rev)
      return string.format('%s  ·  %s  ·  %s  ·  %s', rev.id, rev.phase, rev.status, rev.created_by or '?')
    end,
  }, function(choice)
    if choice then
      M.load(walkthrough_id, choice.id)
    end
  end)
end

--- Open the implementation revision with a visual before/after diff
--- against the current exploration revision attached.
function M.diff(walkthrough_id)
  local root = require('walkthrough-nvim.persist.root').find()

  if not walkthrough_id or walkthrough_id == '' then
    no_id_notice(root, ':WalkthroughDiff {id}')
    return
  end

  local io_mod = require('walkthrough-nvim.persist.io')
  local ok, manifest = pcall(io_mod.read_manifest, root, walkthrough_id)
  if not ok then
    vim.notify('walkthrough: ' .. tostring(manifest), vim.log.levels.ERROR)
    return
  end

  local before_id = manifest.current and manifest.current.exploration
  local after_id = manifest.current and manifest.current.implementation
  if not before_id or not after_id then
    vim.notify(
      'walkthrough: need both an exploration and an implementation revision for "'
        .. walkthrough_id
        .. '" -- run walkthrough-explore and walkthrough-asbuilt first',
      vim.log.levels.WARN
    )
    return
  end

  local before_ok, before_model = io_mod.read_revision(root, walkthrough_id, before_id)
  if not before_ok then
    vim.notify('walkthrough: ' .. tostring(before_model), vim.log.levels.ERROR)
    return
  end
  local after_ok, after_model = io_mod.read_revision(root, walkthrough_id, after_id)
  if not after_ok then
    vim.notify('walkthrough: ' .. tostring(after_model), vim.log.levels.ERROR)
    return
  end

  local diff_mod = require('walkthrough-nvim.model.diff')
  local result = diff_mod.diff(before_model, after_model)

  open_revision(root, walkthrough_id, after_id, { before_id = before_id, after_id = after_id, result = result })
end

--- Close the active walkthrough session, stopping its server.
function M.close()
  local state = require('walkthrough-nvim.ui.state')
  if not state.active() then
    vim.notify('walkthrough: no active session', vim.log.levels.WARN)
    return
  end
  state.clear()
  vim.notify('walkthrough: closed', vim.log.levels.INFO)
end

return M
