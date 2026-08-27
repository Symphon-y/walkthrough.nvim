-- walkthrough-nvim.model.diff — before/after comparison between two
-- walkthrough revisions. Adapted from cartograph.nvim's compare.lua
-- (pure two-graph a/b/both diff); generalized here to components,
-- relationships, and decisions, and to report field-level changes
-- rather than just presence/absence. Pure Lua, no vim.* API.

local M = {}

-- Plain-Lua recursive equality — kept local rather than reaching for a
-- vim.* helper so this module stays usable outside a running editor.
local function deep_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return false
  end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function index_by_id(list)
  local by_id = {}
  for _, entity in ipairs(list or {}) do
    by_id[entity.id] = entity
  end
  return by_id
end

-- Diff one collection (e.g. "components") between two revisions.
-- Fields listed in `compare_fields` determine what counts as "changed"
-- for an id present in both; everything else is ignored (e.g. status,
-- corrections bookkeeping — those are review state, not architecture).
local function diff_collection(before_list, after_list, compare_fields)
  local before_by_id = index_by_id(before_list)
  local after_by_id = index_by_id(after_list)

  local result = { added = {}, removed = {}, changed = {}, unchanged = {} }

  for id, entity in pairs(after_by_id) do
    if not before_by_id[id] then
      result.added[#result.added + 1] = entity
    end
  end

  for id, entity in pairs(before_by_id) do
    local after_entity = after_by_id[id]
    if not after_entity then
      result.removed[#result.removed + 1] = entity
    else
      local changed_fields = {}
      for _, field in ipairs(compare_fields) do
        if not deep_equal(entity[field], after_entity[field]) then
          changed_fields[#changed_fields + 1] = field
        end
      end
      if #changed_fields > 0 then
        result.changed[#result.changed + 1] = { id = id, before = entity, after = after_entity, fields = changed_fields }
      else
        result.unchanged[#result.unchanged + 1] = after_entity
      end
    end
  end

  -- Stable ordering for deterministic output/tests.
  local function by_id_key(x)
    return x.id or (x.after and x.after.id) or ''
  end
  table.sort(result.added, function(a, b) return by_id_key(a) < by_id_key(b) end)
  table.sort(result.removed, function(a, b) return by_id_key(a) < by_id_key(b) end)
  table.sort(result.changed, function(a, b) return by_id_key(a) < by_id_key(b) end)
  table.sort(result.unchanged, function(a, b) return by_id_key(a) < by_id_key(b) end)

  return result
end

--- Diff two walkthrough revisions.
--
-- Note: this compares entities by id only. If the LLM minted a new id
-- for a conceptually-renamed component instead of reusing the old one,
-- it will show here as a remove+add, not a rename — id-reuse discipline
-- is a v0.1 prompt convention, not something this module can verify.
--
-- @return { components = {...}, data_entities = {...}, relationships = {...}, decisions = {...}, summary = {...} }
function M.diff(before, after)
  assert(type(before) == 'table' and type(after) == 'table', 'diff requires two model tables')

  local components = diff_collection(before.components, after.components, { 'name', 'kind', 'role', 'group', 'parent' })
  local data_entities = diff_collection(before.data_entities, after.data_entities, { 'name', 'role', 'fields' })
  local relationships = diff_collection(before.relationships, after.relationships, { 'from', 'to', 'kind', 'data_shape' })
  local decisions = diff_collection(before.decisions, after.decisions, { 'question', 'options' })

  local function counts(section)
    return { added = #section.added, removed = #section.removed, changed = #section.changed }
  end

  return {
    components = components,
    data_entities = data_entities,
    relationships = relationships,
    decisions = decisions,
    summary = {
      components = counts(components),
      data_entities = counts(data_entities),
      relationships = counts(relationships),
      decisions = counts(decisions),
    },
  }
end

return M
