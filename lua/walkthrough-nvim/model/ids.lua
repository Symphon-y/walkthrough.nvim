-- walkthrough-nvim.model.ids — stable id minting for walkthrough entities.
-- Pure Lua. IDs are kind-prefixed slugs (e.g. "component:refund-service"),
-- minted once and expected to be reused verbatim across revisions — unlike
-- cartograph.nvim's file:line-derived node ids, walkthrough entities are
-- curated/human-edited and must survive line-number churn.

local M = {}

--- Turn arbitrary text into a lowercase, dash-separated slug. Splits
--- CamelCase boundaries first (e.g. "RefundService" -> "refund-service",
--- "HTTPServer" -> "http-server") so symbol names read naturally as ids.
function M.slugify(text)
  local s = tostring(text or '')
  s = s:gsub('(%l)(%u)', '%1-%2')      -- fooBar -> foo-Bar
  s = s:gsub('(%u)(%u%l)', '%1-%2')    -- HTTPServer -> HTTP-Server
  s = s:lower()
  s = s:gsub('[^%w]+', '-')
  s = s:gsub('^%-+', ''):gsub('%-+$', '')
  s = s:gsub('%-%-+', '-')
  if s == '' then
    s = 'unnamed'
  end
  return s
end

--- Collect every entity id currently present in a model, across all
--- collections that share the id namespace.
function M.collect(model)
  local ids = {}
  local collections = { 'groups', 'components', 'relationships', 'flows', 'data_lineage', 'decisions', 'assumptions' }
  for _, key in ipairs(collections) do
    for _, entity in ipairs(model[key] or {}) do
      if entity.id then
        ids[entity.id] = true
      end
    end
  end
  return ids
end

--- Mint a new stable id of the form "<kind>:<slug>", disambiguating
--- against ids already present in `model` by appending -2, -3, ...
function M.mint(model, kind, name)
  local ids = M.collect(model)
  local base = kind .. ':' .. M.slugify(name)
  if not ids[base] then
    return base
  end
  local n = 2
  while ids[base .. '-' .. n] do
    n = n + 1
  end
  return base .. '-' .. n
end

return M
