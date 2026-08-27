-- Runs the just-written correction-loop/expl-001.json through the real
-- persist/io.write_revision path (schema validation + manifest
-- bookkeeping), since it was written directly to disk rather than
-- through the plugin -- exactly the situation the walkthrough-explore
-- skill's Claude side is normally in (it only ever writes the revision
-- file; the manifest is the plugin's job the next time something reads
-- it... except nothing currently does that lazily, so this closes that
-- gap for this one hand-run). Run with :source on this file.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local ok, model = io_mod.read_revision(root, 'correction-loop', 'expl-001')
print('read_revision ok=', ok, 'err_or_nothing=', ok and '' or model)
if not ok then
  return
end

local write_ok, err = io_mod.write_revision(root, model)
print('write_revision (validates + updates manifest) ok=', write_ok, 'err=', err)
