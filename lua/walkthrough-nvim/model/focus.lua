-- walkthrough-nvim.model.focus — progressive-disclosure slicing.
-- Adapted from cartograph.nvim's focus.lua (path-tracing/dimming overlay
-- for a call graph); repurposed here to drive "expand this component to
-- see what it's directly connected to" rather than tracing a single path
-- through a homogeneous graph. Pure Lua, no vim.* API — the renderer
-- decides how "active" vs "dimmed" actually looks.

local M = {}

--- Ids of every component/relationship directly touching `id`:
--- the other end of any relationship, and — for a component — its
--- group siblings and parent/children in the nesting hierarchy.
function M.neighbors(model, id)
  local seen = {}
  local result = {}
  local function add(other_id)
    if other_id and other_id ~= id and not seen[other_id] then
      seen[other_id] = true
      result[#result + 1] = other_id
    end
  end

  for _, rel in ipairs(model.relationships or {}) do
    if rel.from == id then
      add(rel.to)
      add(rel.id)
    elseif rel.to == id then
      add(rel.from)
      add(rel.id)
    end
  end

  for _, c in ipairs(model.components or {}) do
    if c.id == id then
      add(c.group)
      add(c.parent)
    elseif c.group and c.group == id then
      add(c.id)
    elseif c.parent and c.parent == id then
      add(c.id)
    end
  end

  return result
end

--- Add `id` and its immediate neighbors to an expanded-set, returning a
--- new set (does not mutate `expanded`).
-- expanded: id -> true
function M.expand(model, expanded, id)
  local next_set = {}
  for k in pairs(expanded or {}) do
    next_set[k] = true
  end
  next_set[id] = true
  for _, neighbor_id in ipairs(M.neighbors(model, id)) do
    next_set[neighbor_id] = true
  end
  return next_set
end

--- Append an id to a drill-down breadcrumb path, returning a new path.
function M.step(path, id)
  local next_path = {}
  for _, existing in ipairs(path or {}) do
    next_path[#next_path + 1] = existing
  end
  next_path[#next_path + 1] = id
  return next_path
end

--- Compute the active/dimmed overlay for a breadcrumb path: everything
--- on the path plus the last step's immediate neighbors is "active",
--- everything else in the model is "dimmed".
-- @return { active = {id -> true}, dimmed = {id -> true} }
function M.overlay(model, path)
  local active = {}
  for _, id in ipairs(path or {}) do
    active[id] = true
  end
  local last = path and path[#path]
  if last then
    for _, neighbor_id in ipairs(M.neighbors(model, last)) do
      active[neighbor_id] = true
    end
  end

  local dimmed = {}
  local collections = { 'groups', 'components', 'relationships', 'flows', 'data_lineage', 'decisions', 'assumptions' }
  for _, key in ipairs(collections) do
    for _, entity in ipairs(model[key] or {}) do
      if entity.id and not active[entity.id] then
        dimmed[entity.id] = true
      end
    end
  end

  return { active = active, dimmed = dimmed }
end

return M
