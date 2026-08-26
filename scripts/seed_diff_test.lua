-- Seeds "diff-test" with an exploration revision AND an implementation
-- revision (reusing tests/fixtures/diff-before.json / diff-after.json,
-- built in Phase 0 specifically to exercise every diff case: added,
-- removed, changed, and unchanged components/relationships/decisions),
-- so :WalkthroughDiff has something real to render. Evidence swapped to
-- point at a real file in this repo. Run with :source on this file.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local real_evidence = { file = 'lua/walkthrough-nvim/model/schema.lua', line = 1 }

local function load_and_seed(fixture_name)
  local path = root .. '/tests/fixtures/' .. fixture_name
  local model = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  model.walkthrough_id = 'diff-test'
  for _, c in ipairs(model.components) do
    c.evidence[1] = real_evidence
  end
  for _, r in ipairs(model.relationships or {}) do
    r.evidence[1] = real_evidence
  end
  local ok, err = io_mod.write_revision(root, model)
  print(fixture_name, 'ok=', ok, 'err=', err)
end

load_and_seed('diff-before.json') -- expl-002, phase=exploration
load_and_seed('diff-after.json') -- impl-001, phase=implementation
