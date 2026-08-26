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

  it('reports no differences when diffing a model against itself', function()
    local self_diff = diff.diff(before, before)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.components)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.relationships)
    assert.same({ added = 0, removed = 0, changed = 0 }, self_diff.summary.decisions)
  end)
end)
