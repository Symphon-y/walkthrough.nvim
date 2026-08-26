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

--- Open a walkthrough's current exploration revision: starts the local
--- server, points a browser at its component/architecture diagram, and
--- wires jump-to-source back into this Neovim instance.
function M.open(walkthrough_id)
  local root_mod = require('walkthrough-nvim.persist.root')
  local io_mod = require('walkthrough-nvim.persist.io')
  local state = require('walkthrough-nvim.ui.state')

  local root = root_mod.find()

  if not walkthrough_id or walkthrough_id == '' then
    local names = io_mod.list_walkthroughs(root)
    if #names == 0 then
      vim.notify('walkthrough: no walkthroughs found for this repo yet', vim.log.levels.WARN)
    else
      vim.notify('walkthrough: usage :WalkthroughOpen {id}\navailable: ' .. table.concat(names, ', '), vim.log.levels.WARN)
    end
    return
  end

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

  local read_ok, model = io_mod.read_revision(root, walkthrough_id, revision_id)
  if not read_ok then
    vim.notify('walkthrough: ' .. tostring(model), vim.log.levels.ERROR)
    return
  end

  state.clear() -- stop any previously open session's server first

  state.new(root, walkthrough_id, model)
  local server = require('walkthrough-nvim.server.server').start({
    engine = require('walkthrough-nvim.server.bridge'),
  })
  state.session.server = server

  require('walkthrough-nvim.server.browser').open(server:url('/'))
  vim.notify('walkthrough: opened ' .. walkthrough_id .. ' (' .. revision_id .. ')', vim.log.levels.INFO)
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
