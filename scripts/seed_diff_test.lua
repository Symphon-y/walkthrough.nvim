-- Seeds "diff-test" with an exploration revision AND an implementation
-- revision (reusing tests/fixtures/diff-before.json / diff-after.json,
-- built in Phase 0 specifically to exercise every diff case: added,
-- removed, changed, and unchanged components/relationships/decisions),
-- so :WalkthroughDiff has something real to render.
--
-- Each entity gets DISTINCT evidence pointing at a different real file in
-- this repo (not a single shared placeholder) -- the whole point of this
-- seed is to demonstrate that different diff rows reveal to different
-- places; giving everything the same evidence would silently defeat that.
-- Run with :source on this file.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local EVIDENCE_BY_ID = {
  ['component:refund-controller'] = { file = 'lua/walkthrough-nvim/init.lua', line = 1 },
  ['component:refund-service'] = { file = 'lua/walkthrough-nvim/server/bridge.lua', line = 1 },
  ['component:payment-gateway-client'] = { file = 'lua/walkthrough-nvim/server/browser.lua', line = 1 },
  ['component:refund-orchestrator'] = { file = 'lua/walkthrough-nvim/ui/correct.lua', line = 1 },

  ['rel:refund-controller--calls--refund-service'] = { file = 'lua/walkthrough-nvim/server/protocol.lua', line = 1 },
  ['rel:refund-service--calls--payment-gateway'] = { file = 'lua/walkthrough-nvim/server/http_wire.lua', line = 1 },
  ['rel:refund-service--calls--refund-orchestrator'] = { file = 'lua/walkthrough-nvim/model/diff.lua', line = 1 },

  ['decision:sync-vs-async-refund'] = { file = 'lua/walkthrough-nvim/model/schema.lua', line = 1 },
  ['decision:storage-format'] = { file = 'lua/walkthrough-nvim/persist/io.lua', line = 1 },
  ['decision:auth-boundary'] = { file = 'lua/walkthrough-nvim/model/corrections.lua', line = 1 },
  ['decision:retry-policy'] = { file = 'lua/walkthrough-nvim/persist/paths.lua', line = 1 },
}

local function apply_distinct_evidence(list)
  for _, entity in ipairs(list or {}) do
    local ev = EVIDENCE_BY_ID[entity.id]
    if ev then
      entity.evidence = { ev }
    end
  end
end

local function load_and_seed(fixture_name)
  local path = root .. '/tests/fixtures/' .. fixture_name
  local model = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  model.walkthrough_id = 'diff-test'
  apply_distinct_evidence(model.components)
  apply_distinct_evidence(model.relationships)
  apply_distinct_evidence(model.decisions)
  local ok, err = io_mod.write_revision(root, model)
  print(fixture_name, 'ok=', ok, 'err=', err)
end

load_and_seed('diff-before.json') -- expl-002, phase=exploration
load_and_seed('diff-after.json') -- impl-001, phase=implementation
