-- Seeds a "smoke-test-2" walkthrough whose evidence points at a real file
-- in this repo (so :WalkthroughOpen's reveal jumps somewhere real instead
-- of a fake .cs path). Run with :source on this file from within Neovim.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local fixture_path = root .. '/tests/fixtures/valid-full.json'
local model = vim.json.decode(table.concat(vim.fn.readfile(fixture_path), '\n'))
model.walkthrough_id = 'smoke-test-2'
model.revision_id = 'expl-001'

local real_evidence = { file = 'lua/walkthrough-nvim/model/schema.lua', line = 1 }
for _, c in ipairs(model.components) do
  c.evidence[1] = real_evidence
end
for _, r in ipairs(model.relationships) do
  r.evidence[1] = real_evidence
end

local ok, err = io_mod.write_revision(root, model)
print('write_revision ok=', ok, 'err=', err)
