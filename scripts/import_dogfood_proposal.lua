-- Runs the just-written correction-loop/prop-001.json (the propose-feature
-- dogfood) through the real persist/io.write_revision path -- same
-- reasoning as import_dogfood_walkthrough.lua: this proves the hand-
-- written proposal actually passes real schema validation and lands in
-- the manifest correctly, not just that it's syntactically valid JSON.
-- Run with :source on this file.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local ok, model = io_mod.read_revision(root, 'correction-loop', 'prop-001')
print('read_revision ok=', ok, 'err_or_nothing=', ok and '' or model)
if not ok then
  return
end

local write_ok, err = io_mod.write_revision(root, model)
print('write_revision (validates + updates manifest) ok=', write_ok, 'err=', err)
