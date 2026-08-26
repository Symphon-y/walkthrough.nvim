-- walkthrough-nvim.ui.correct — apply an engineer correction to the
-- active session's model and persist it back to the same revision file
-- in place. Claude never edits an existing revision file (only writes
-- new ones), so this and the LLM never race on the same file -- see
-- model/corrections.lua for the status-transition rules this wraps.

local M = {}

local state = require('walkthrough-nvim.ui.state')
local corrections = require('walkthrough-nvim.model.corrections')
local io_mod = require('walkthrough-nvim.persist.io')

local function persist_current()
  return io_mod.write_revision(state.session.root, state.session.model)
end

--- Engineer explicitly confirms an entity is correct.
function M.accept(entity_id)
  if not state.active() then
    return false, 'no active session'
  end
  local ok, err = corrections.set_status(state.session.model, entity_id, 'accepted')
  if not ok then
    return false, err
  end
  return persist_current()
end

--- Engineer flags an entity as wrong, with no proposed fix yet.
function M.challenge(entity_id)
  if not state.active() then
    return false, 'no active session'
  end
  local _, err = corrections.add_correction(state.session.model, { target = entity_id, created_by = 'engineer' })
  if err then
    return false, err
  end
  return persist_current()
end

--- Engineer supplies a concrete correction note for the LLM to reconcile.
function M.correct(entity_id, note)
  if not state.active() then
    return false, 'no active session'
  end
  if type(note) ~= 'string' or note == '' then
    return false, 'correction note must not be empty'
  end
  local _, err = corrections.add_correction(state.session.model, {
    target = entity_id,
    engineer_note = note,
    created_by = 'engineer',
  })
  if err then
    return false, err
  end
  return persist_current()
end

return M
