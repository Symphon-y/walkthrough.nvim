-- walkthrough-nvim.model.schema — enums and structural validation for a
-- walkthrough revision. Pure Lua: no vim.* API, no I/O. Consumes/produces
-- plain tables so it can be unit-tested headless and reused by both the
-- Neovim plugin and any tooling that shells out to it.

local M = {}

M.SCHEMA_VERSION = 1

M.PHASE = { EXPLORATION = 'exploration', IMPLEMENTATION = 'implementation', PROPOSAL = 'proposal' }

M.REVISION_STATUS = { DRAFT = 'draft', CORRECTED = 'corrected', RECONCILED = 'reconciled', FINAL = 'final' }

-- Shared across components, relationships, decisions, and assumptions.
-- NB: STATUS.PROPOSED (lowercase 'proposed', "the LLM asserted it, not yet
-- reviewed") is unrelated to CLAIM_TYPE.PROPOSED (uppercase, "doesn't
-- exist yet") below and PHASE.PROPOSAL above -- three different concepts
-- that happen to share an English word. The existing all-caps/all-lower
-- casing convention between CLAIM_TYPE and STATUS already disambiguates
-- them in every JSON file; not worth a rename to dodge a word collision.
M.STATUS = {
  PROPOSED = 'proposed',
  ACCEPTED = 'accepted',
  CHALLENGED = 'challenged',
  CORRECTED = 'corrected',
  UNRESOLVED = 'unresolved',
}

-- PROPOSED: a not-yet-built entity in a "proposal" revision. Unlike the
-- other three, this is not a point on a confidence-in-existing-reality
-- scale -- it's a different signal entirely ("nothing to cite, this
-- doesn't exist yet"), which is also why it renders with its own visual
-- treatment (web/renderer_component.js) rather than another step on the
-- OBSERVED/INFERRED/UNKNOWN fill ramp.
M.CLAIM_TYPE = { OBSERVED = 'OBSERVED', INFERRED = 'INFERRED', UNKNOWN = 'UNKNOWN', PROPOSED = 'PROPOSED' }

M.CONFIDENCE = { HIGH = 'high', MEDIUM = 'medium', LOW = 'low' }

M.COMPONENT_KIND = { COMPONENT = 'component', BOUNDARY = 'boundary', EXTERNAL = 'external' }

M.RELATIONSHIP_KIND = {
  CALLS = 'calls',
  DEPENDS_ON = 'depends_on',
  PUBLISHES = 'publishes',
  SUBSCRIBES = 'subscribes',
  READS = 'reads',
  WRITES = 'writes',
  -- ER relationships between two data_entities. Named after the ORM
  -- association vocabulary (Rails/ActiveRecord etc.) most engineers
  -- already know, rather than requiring crow's-foot visual notation.
  -- reads/writes above already cover "component touches data entity" --
  -- no separate kind needed for that, it's the same relationships[]
  -- array either way (see data_entities below).
  HAS_ONE = 'has_one',
  HAS_MANY = 'has_many',
  BELONGS_TO = 'belongs_to',
  MANY_TO_MANY = 'many_to_many',
}

M.DECISION_OUTCOME = { CHOSEN = 'chosen', REJECTED = 'rejected' }

local function set_of(tbl)
  local s = {}
  for _, v in pairs(tbl) do
    s[v] = true
  end
  return s
end

local STATUS_SET = set_of(M.STATUS)
local CLAIM_TYPE_SET = set_of(M.CLAIM_TYPE)
local CONFIDENCE_SET = set_of(M.CONFIDENCE)
local COMPONENT_KIND_SET = set_of(M.COMPONENT_KIND)
local RELATIONSHIP_KIND_SET = set_of(M.RELATIONSHIP_KIND)
local DECISION_OUTCOME_SET = set_of(M.DECISION_OUTCOME)
local PHASE_SET = set_of(M.PHASE)
local REVISION_STATUS_SET = set_of(M.REVISION_STATUS)

local function is_nonempty_string(v)
  return type(v) == 'string' and v ~= ''
end

-- Deferred require avoids a load-order cycle: evidence.lua requires this
-- module for CLAIM_TYPE.
local function evidence_mod()
  return require('walkthrough-nvim.model.evidence')
end

-- Evidence entries are shared across every claim-bearing entity.
-- { file = "src/x.cs", line = 42 (optional), symbol = "X.Y" (optional) }
local function check_evidence(evidence, path, errors)
  local errs = evidence_mod().validate_list(evidence, path)
  for _, e in ipairs(errs) do
    errors[#errors + 1] = e
  end
end

-- OBSERVED claims must never look like objectively verified fact without
-- backing evidence — this is the mechanical half of the confidence
-- contract; the human correction loop covers the rest.
local function check_claim(entity, path, errors)
  if entity.claim_type ~= nil and not CLAIM_TYPE_SET[entity.claim_type] then
    errors[#errors + 1] = path .. '.claim_type: must be one of OBSERVED|INFERRED|UNKNOWN|PROPOSED'
  end
  if entity.confidence ~= nil and not CONFIDENCE_SET[entity.confidence] then
    errors[#errors + 1] = path .. '.confidence: must be one of high|medium|low'
  end
  if entity.status ~= nil and not STATUS_SET[entity.status] then
    errors[#errors + 1] = path .. '.status: must be one of proposed|accepted|challenged|corrected|unresolved'
  end
  local errs = evidence_mod().check_claim_evidence(entity.claim_type, entity.evidence, path)
  for _, e in ipairs(errs) do
    errors[#errors + 1] = e
  end
end

local function collect_and_check_ids(model, errors)
  local ids = {}
  local function claim(id, path)
    if not is_nonempty_string(id) then
      errors[#errors + 1] = path .. '.id: required non-empty string'
      return
    end
    if ids[id] then
      errors[#errors + 1] = path .. '.id: duplicate id "' .. id .. '" (already used by ' .. ids[id] .. ')'
    else
      ids[id] = path
    end
  end

  for i, g in ipairs(model.groups or {}) do
    claim(g.id, string.format('groups[%d]', i))
  end
  for i, c in ipairs(model.components or {}) do
    claim(c.id, string.format('components[%d]', i))
  end
  for i, e in ipairs(model.data_entities or {}) do
    claim(e.id, string.format('data_entities[%d]', i))
  end
  for i, r in ipairs(model.relationships or {}) do
    claim(r.id, string.format('relationships[%d]', i))
  end
  for i, f in ipairs(model.flows or {}) do
    claim(f.id, string.format('flows[%d]', i))
  end
  for i, l in ipairs(model.data_lineage or {}) do
    claim(l.id, string.format('data_lineage[%d]', i))
  end
  for i, d in ipairs(model.decisions or {}) do
    claim(d.id, string.format('decisions[%d]', i))
  end
  for i, a in ipairs(model.assumptions or {}) do
    claim(a.id, string.format('assumptions[%d]', i))
  end
  return ids
end

local function check_components(model, ids, errors)
  for i, c in ipairs(model.components or {}) do
    local path = string.format('components[%d]', i)
    if not is_nonempty_string(c.name) then
      errors[#errors + 1] = path .. '.name: required non-empty string'
    end
    if c.kind ~= nil and not COMPONENT_KIND_SET[c.kind] then
      errors[#errors + 1] = path .. '.kind: must be one of component|boundary|external'
    end
    if c.group ~= nil and not ids[c.group] then
      errors[#errors + 1] = path .. '.group: references unknown id "' .. tostring(c.group) .. '"'
    end
    if c.parent ~= nil and not ids[c.parent] then
      errors[#errors + 1] = path .. '.parent: references unknown id "' .. tostring(c.parent) .. '"'
    end
    check_claim(c, path, errors)
  end
end

-- A data entity's `fields` is deliberately light -- a short list of
-- notable columns (e.g. primary/foreign keys), not a full column/type
-- dump. The walkthrough orients the reader; it doesn't replace the real
-- schema/migrations.
local function check_data_entities(model, errors)
  for i, e in ipairs(model.data_entities or {}) do
    local path = string.format('data_entities[%d]', i)
    if not is_nonempty_string(e.name) then
      errors[#errors + 1] = path .. '.name: required non-empty string'
    end
    if e.fields ~= nil then
      if type(e.fields) ~= 'table' then
        errors[#errors + 1] = path .. '.fields: must be an array'
      else
        for j, f in ipairs(e.fields) do
          if not is_nonempty_string(f.name) then
            errors[#errors + 1] = string.format('%s.fields[%d].name: required non-empty string', path, j)
          end
        end
      end
    end
    check_claim(e, path, errors)
  end
end

local function check_relationships(model, ids, errors)
  for i, r in ipairs(model.relationships or {}) do
    local path = string.format('relationships[%d]', i)
    if not is_nonempty_string(r.from) or not ids[r.from] then
      errors[#errors + 1] = path .. '.from: references unknown id "' .. tostring(r.from) .. '"'
    end
    if not is_nonempty_string(r.to) or not ids[r.to] then
      errors[#errors + 1] = path .. '.to: references unknown id "' .. tostring(r.to) .. '"'
    end
    if r.kind ~= nil and not RELATIONSHIP_KIND_SET[r.kind] then
      errors[#errors + 1] = path .. '.kind: must be one of calls|depends_on|publishes|subscribes|reads|writes|has_one|has_many|belongs_to|many_to_many'
    end
    check_claim(r, path, errors)
  end
end

local function check_decisions(model, errors)
  for i, d in ipairs(model.decisions or {}) do
    local path = string.format('decisions[%d]', i)
    if not is_nonempty_string(d.question) then
      errors[#errors + 1] = path .. '.question: required non-empty string'
    end
    if d.options ~= nil then
      if type(d.options) ~= 'table' then
        errors[#errors + 1] = path .. '.options: must be an array'
      else
        for j, o in ipairs(d.options) do
          local op = string.format('%s.options[%d]', path, j)
          if not is_nonempty_string(o.option) then
            errors[#errors + 1] = op .. '.option: required non-empty string'
          end
          if not DECISION_OUTCOME_SET[o.outcome] then
            errors[#errors + 1] = op .. '.outcome: must be chosen|rejected'
          end
          check_evidence(o.evidence, op .. '.evidence', errors)
        end
      end
    end
    check_claim(d, path, errors)
  end
end

local function check_assumptions(model, errors)
  for i, a in ipairs(model.assumptions or {}) do
    local path = string.format('assumptions[%d]', i)
    if not is_nonempty_string(a.statement) then
      errors[#errors + 1] = path .. '.statement: required non-empty string'
    end
    check_claim(a, path, errors)
  end
end

local function check_corrections(model, ids, errors)
  for i, corr in ipairs(model.corrections or {}) do
    local path = string.format('corrections[%d]', i)
    if not is_nonempty_string(corr.id) then
      errors[#errors + 1] = path .. '.id: required non-empty string'
    end
    if not is_nonempty_string(corr.target) or not ids[corr.target] then
      errors[#errors + 1] = path .. '.target: references unknown id "' .. tostring(corr.target) .. '"'
    end
    if corr.resolved ~= nil and type(corr.resolved) ~= 'boolean' then
      errors[#errors + 1] = path .. '.resolved: must be a boolean when present'
    end
  end
end

--- Validate a walkthrough revision table against the schema.
-- @return ok boolean
-- @return errors string[] empty when ok
function M.validate(model)
  local errors = {}

  if type(model) ~= 'table' then
    return false, { 'model must be a table' }
  end

  if model.schema_version ~= M.SCHEMA_VERSION then
    errors[#errors + 1] = 'schema_version: expected ' .. M.SCHEMA_VERSION .. ', got ' .. tostring(model.schema_version)
  end
  if not is_nonempty_string(model.walkthrough_id) then
    errors[#errors + 1] = 'walkthrough_id: required non-empty string'
  end
  if not is_nonempty_string(model.revision_id) then
    errors[#errors + 1] = 'revision_id: required non-empty string'
  end
  if not PHASE_SET[model.phase] then
    errors[#errors + 1] = 'phase: must be exploration|implementation|proposal'
  end
  if not REVISION_STATUS_SET[model.status] then
    errors[#errors + 1] = 'status: must be draft|corrected|reconciled|final'
  end

  local ids = collect_and_check_ids(model, errors)
  check_components(model, ids, errors)
  check_data_entities(model, errors)
  check_relationships(model, ids, errors)
  check_decisions(model, errors)
  check_assumptions(model, errors)
  check_corrections(model, ids, errors)

  return #errors == 0, errors
end

return M
