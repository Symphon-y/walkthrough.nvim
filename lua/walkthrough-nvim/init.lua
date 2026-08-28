local M = {}

local config = require('walkthrough-nvim.config')

--- Self-heal this plugin's Claude Code skills (~/.claude/skills/) on every
--- setup() call, silently unless something actually changed or hit a
--- conflict that needs :WalkthroughSetup! to resolve. Because the plugin's
--- own lazy.nvim spec lazy-loads on `cmd = {...}`, this runs the first time
--- any :Walkthrough* command fires in a session, not on every Neovim
--- startup -- and it keeps skills in sync across plugin updates without
--- requiring a manual step every time a SKILL.md changes. Wrapped in pcall
--- so a filesystem hiccup here can never break the rest of the plugin.
local function auto_heal_skills()
  local ok, result = pcall(function()
    return require('walkthrough-nvim.skills').link_skills({ force = false })
  end)
  if not ok then
    return
  end

  local changed = {}
  for name, entry in pairs(result) do
    if entry.outcome ~= 'up_to_date' then
      changed[#changed + 1] = name .. ': ' .. entry.outcome
    end
  end
  if #changed > 0 then
    table.sort(changed)
    vim.notify('walkthrough: skills updated\n  ' .. table.concat(changed, '\n  '), vim.log.levels.INFO)
  end
end

function M.setup(opts)
  config.setup(opts)
  auto_heal_skills()
end

--- Install/repair this plugin's Claude Code skills into ~/.claude/skills/,
--- Claude's global skill directory -- backs :WalkthroughSetup[!]. Unlike
--- the silent auto-heal above, this always reports full per-skill status,
--- since it's a deliberate action the user just took.
function M.setup_skills(force)
  local skills = require('walkthrough-nvim.skills')
  local result = skills.link_skills({ force = force })

  local lines = {}
  for name, entry in pairs(result) do
    lines[#lines + 1] = string.format('  %s: %s', name, entry.outcome)
  end
  table.sort(lines)
  vim.notify('walkthrough: skills\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
  return result
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

--- Open `after_phase`'s current revision with a visual before/after diff
--- against `before_phase`'s current revision attached. Both default to
--- exploration/implementation (the original Phase 4 behavior); pass
--- 'proposal' as either to review a walkthrough-propose revision instead
--- -- model/diff.lua and the delta renderer are phase-agnostic already,
--- so no other code needed to change for this to work.
function M.diff(walkthrough_id, before_phase, after_phase)
  before_phase = before_phase or 'exploration'
  after_phase = after_phase or 'implementation'

  local root = require('walkthrough-nvim.persist.root').find()

  if not walkthrough_id or walkthrough_id == '' then
    no_id_notice(root, ':WalkthroughDiff {id} [before-phase] [after-phase]')
    return
  end

  local io_mod = require('walkthrough-nvim.persist.io')
  local ok, manifest = pcall(io_mod.read_manifest, root, walkthrough_id)
  if not ok then
    vim.notify('walkthrough: ' .. tostring(manifest), vim.log.levels.ERROR)
    return
  end

  local before_id = manifest.current and manifest.current[before_phase]
  local after_id = manifest.current and manifest.current[after_phase]
  if not before_id or not after_id then
    local missing = not before_id and before_phase or after_phase
    vim.notify(
      'walkthrough: no current "'
        .. missing
        .. '" revision for "'
        .. walkthrough_id
        .. '" -- write one first (walkthrough-explore/-propose/-asbuilt, as appropriate)',
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
