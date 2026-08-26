-- walkthrough-nvim.model.corrections — apply engineer corrections to a
-- walkthrough revision. Pure Lua, mutates and returns the same model
-- table (no I/O — persist/io.lua owns writing the result to disk).
--
-- A correction never rewrites the LLM's original claim; it appends a
-- correction record and flips the target entity's status. The next
-- reconciliation pass (a fresh revision, written by the LLM) is what
-- actually incorporates the correction into the model.

local M = {}

local schema = require('walkthrough-nvim.model.schema')

local ENTITY_COLLECTIONS = { 'groups', 'components', 'relationships', 'flows', 'data_lineage', 'decisions', 'assumptions' }

--- Find an entity by id anywhere in the model.
-- @return entity table|nil
-- @return collection_name string|nil
function M.find_entity(model, id)
  for _, key in ipairs(ENTITY_COLLECTIONS) do
    for _, entity in ipairs(model[key] or {}) do
      if entity.id == id then
        return entity, key
      end
    end
  end
  return nil, nil
end

--- Directly set an entity's status (used by simple accept/challenge
--- actions that don't carry a written correction note).
function M.set_status(model, id, status)
  assert(schema.STATUS[tostring(status):upper()] ~= nil, 'invalid status: ' .. tostring(status))
  local entity = M.find_entity(model, id)
  if not entity then
    return false, 'unknown id: ' .. tostring(id)
  end
  entity.status = status
  return true, nil
end

local function next_correction_id(model)
  local max_n = 0
  for _, c in ipairs(model.corrections or {}) do
    local n = tonumber(tostring(c.id):match('(%d+)$'))
    if n and n > max_n then
      max_n = n
    end
  end
  return string.format('correction:%04d', max_n + 1)
end

--- Append a correction and flip the target's status.
-- correction: { target = id, target_field? , kind?, engineer_note?, created_by? }
-- A non-empty engineer_note moves the target straight to "corrected"
-- (there's a concrete fix to reconcile); an empty note just "challenged"
-- (something's flagged wrong, no proposed fix yet).
-- @return correction table|nil, err string|nil
function M.add_correction(model, correction)
  assert(type(correction) == 'table', 'correction must be a table')
  local target = M.find_entity(model, correction.target)
  if not target then
    return nil, 'unknown target id: ' .. tostring(correction.target)
  end

  model.corrections = model.corrections or {}
  local record = {
    id = correction.id or next_correction_id(model),
    target = correction.target,
    target_field = correction.target_field,
    kind = correction.kind,
    engineer_note = correction.engineer_note,
    created_at = correction.created_at,
    created_by = correction.created_by,
    resolved = false,
    resolved_in_revision = nil,
  }
  table.insert(model.corrections, record)

  if type(correction.engineer_note) == 'string' and correction.engineer_note ~= '' then
    target.status = schema.STATUS.CORRECTED
  else
    target.status = schema.STATUS.CHALLENGED
  end

  return record, nil
end

--- Mark a correction resolved once a later revision addresses it.
function M.resolve_correction(model, correction_id, resolved_in_revision)
  for _, c in ipairs(model.corrections or {}) do
    if c.id == correction_id then
      c.resolved = true
      c.resolved_in_revision = resolved_in_revision
      return true, nil
    end
  end
  return false, 'unknown correction id: ' .. tostring(correction_id)
end

--- List corrections that haven't been resolved in a later revision yet —
--- exactly what a reconciliation pass needs to address.
function M.open_corrections(model)
  local open = {}
  for _, c in ipairs(model.corrections or {}) do
    if not c.resolved then
      open[#open + 1] = c
    end
  end
  return open
end

return M
