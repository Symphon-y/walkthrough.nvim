local diff = require('walkthrough-nvim.model.diff')

local function load_fixture(name)
  local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
  local path = here .. '/fixtures/' .. name
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, '\n'))
end

local function ids_of(list)
  local out = {}
  for _, entity in ipairs(list) do
    out[#out + 1] = entity.id
  end
  return out
end

describe('walkthrough-nvim.model.diff', function()
  local before = load_fixture('diff-before.json')
  local after = load_fixture('diff-after.json')
  local result = diff.diff(before, after)

  describe('components', function()
    it('detects the added component', function()
      assert.same({ 'component:refund-orchestrator' }, ids_of(result.components.added))
    end)

    it('detects the removed component', function()
      assert.same({ 'component:payment-gateway-client' }, ids_of(result.components.removed))
    end)

    it('detects the changed component and names the changed field', function()
      assert.equals(1, #result.components.changed)
      local changed = result.components.changed[1]
      assert.equals('component:refund-service', changed.id)
      assert.same({ 'role' }, changed.fields)
    end)

    it('leaves the untouched component unchanged', function()
      assert.same({ 'component:refund-controller' }, ids_of(result.components.unchanged))
    end)
  end)

  describe('relationships', function()
    it('detects added and removed relationships', function()
      assert.same({ 'rel:refund-service--calls--refund-orchestrator' }, ids_of(result.relationships.added))
      assert.same({ 'rel:refund-service--calls--payment-gateway' }, ids_of(result.relationships.removed))
    end)

    it('leaves the untouched relationship unchanged', function()
      assert.same({ 'rel:refund-controller--calls--refund-service' }, ids_of(result.relationships.unchanged))
    end)
  end)

  describe('decisions', function()
    it('detects the added and removed decision', function()
      assert.same({ 'decision:retry-policy' }, ids_of(result.decisions.added))
      assert.same({ 'decision:storage-format' }, ids_of(result.decisions.removed))
    end)

    it('detects the changed decision (options differ)', function()
      assert.equals(1, #result.decisions.changed)
      assert.equals('decision:auth-boundary', result.decisions.changed[1].id)
      assert.same({ 'options' }, result.decisions.changed[1].fields)
    end)

    it('leaves the untouched decision unchanged', function()
      assert.same({ 'decision:sync-vs-async-refund' }, ids_of(result.decisions.unchanged))
    end)
  end)

  describe('summary', function()
    it('counts added/removed/changed per section', function()
      assert.same({ added = 1, removed = 1, changed = 1 }, result.summary.components)
      assert.same({ added = 1, removed = 1, changed = 0 }, result.summary.relationships)
      assert.same({ added = 1, removed = 1, changed = 1 }, result.summary.decisions)
    end)
  end)

  -- Self-contained inline tables (not the shared diff-before/after.json
  -- fixtures, which are already large) -- the first real exercise of
  -- diff_collection against data_entities input, even though the
  -- function itself needs no change to support it.
  describe('data_entities', function()
    it('classifies added/removed/changed/unchanged the same as every other section', function()
      local before_data = {
        data_entities = {
          { id = 'data:patient', name = 'Patient', role = 'One row per patient.' },
          { id = 'data:refund_ledger', name = 'RefundLedger', role = 'Audit trail.' },
        },
      }
      local after_data = {
        data_entities = {
          { id = 'data:patient', name = 'Patient', role = 'One row per patient.' }, -- unchanged
          { id = 'data:refund_ledger', name = 'RefundLedger', role = 'Audit trail, now with a status column.' }, -- changed
          { id = 'data:cohort', name = 'Cohort', role = 'A saved patient cohort.' }, -- added
        },
      }
      -- data:refund_ledger from before_data is absent from after_data's
      -- surviving set only if omitted; here it's present-but-changed, so
      -- there's no "removed" case in this fixture -- add one explicitly.
      before_data.data_entities[3] = { id = 'data:legacy_export', name = 'LegacyExport', role = 'Superseded.' }

      local result = diff.diff(before_data, after_data)

      assert.same({ 'data:cohort' }, ids_of(result.data_entities.added))
      assert.same({ 'data:legacy_export' }, ids_of(result.data_entities.removed))
      assert.equals(1, #result.data_entities.changed)
      assert.equals('data:refund_ledger', result.data_entities.changed[1].id)
      assert.same({ 'role' }, result.data_entities.changed[1].fields)
      assert.same({ 'data:patient' }, ids_of(result.data_entities.unchanged))
      assert.same({ added = 1, removed = 1, changed = 1 }, result.summary.data_entities)
    end)
  end)

  it('reports no differences when diffing a model against itself', function()
    local self_diff = diff.diff(before, before)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.components)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.relationships)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.decisions)
  end)

  -- Design-invariant guard, not a code requirement: diff.lua compares two
  -- model tables and has never looked at `phase` (verified by reading the
  -- source, not assumed) -- this pins that down so a future change can't
  -- quietly make it phase-aware. Reuses the same before/after fixtures
  -- with their `phase` fields overridden to exploration/proposal instead
  -- of exploration/implementation; the classification must come out
  -- identical either way.
  it('is phase-agnostic: classifies identically regardless of which phases the two models came from', function()
    local before_as_exploration = vim.deepcopy(before)
    local after_as_proposal = vim.deepcopy(after)
    after_as_proposal.phase = 'proposal'
    after_as_proposal.revision_id = 'prop-001'

    local result_via_proposal = diff.diff(before_as_exploration, after_as_proposal)

    assert.same(ids_of(result.components.added), ids_of(result_via_proposal.components.added))
    assert.same(ids_of(result.components.removed), ids_of(result_via_proposal.components.removed))
    assert.equals(#result.components.changed, #result_via_proposal.components.changed)
    assert.same(result.summary, result_via_proposal.summary)
  end)
end)
