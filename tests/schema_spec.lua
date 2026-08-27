local schema = require('walkthrough-nvim.model.schema')

local function load_fixture(name)
  local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
  local path = here .. '/fixtures/' .. name
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, '\n'))
end

local function has_error_containing(errors, substring)
  for _, e in ipairs(errors) do
    if e:find(substring, 1, true) then
      return true
    end
  end
  return false
end

describe('walkthrough-nvim.model.schema', function()
  it('exposes the expected enums', function()
    assert.equals(1, schema.SCHEMA_VERSION)
    assert.equals('exploration', schema.PHASE.EXPLORATION)
    assert.equals('implementation', schema.PHASE.IMPLEMENTATION)
    assert.equals('proposal', schema.PHASE.PROPOSAL)
    assert.equals('OBSERVED', schema.CLAIM_TYPE.OBSERVED)
    assert.equals('PROPOSED', schema.CLAIM_TYPE.PROPOSED)
  end)

  it('accepts a minimal valid model', function()
    local ok, errors = schema.validate(load_fixture('valid-minimal.json'))
    assert.is_true(ok)
    assert.same({}, errors)
  end)

  it('accepts a fully populated valid model', function()
    local ok, errors = schema.validate(load_fixture('valid-full.json'))
    assert.is_true(ok, table.concat(errors, '; '))
    assert.same({}, errors)
  end)

  it('accepts a PROPOSED component with no evidence, in a proposal-phase revision', function()
    local ok, errors = schema.validate(load_fixture('valid-proposal.json'))
    assert.is_true(ok, table.concat(errors, '; '))
    assert.same({}, errors)
  end)

  it('rejects an OBSERVED claim with no evidence', function()
    local ok, errors = schema.validate(load_fixture('invalid-missing-evidence.json'))
    assert.is_false(ok)
    assert.truthy(has_error_containing(errors, 'OBSERVED claims require at least one evidence entry'))
  end)

  it('rejects an invalid revision status', function()
    local ok, errors = schema.validate(load_fixture('invalid-bad-status.json'))
    assert.is_false(ok)
    assert.truthy(has_error_containing(errors, 'status: must be draft|corrected|reconciled|final'))
  end)

  it('rejects a relationship pointing at an unknown component id', function()
    local ok, errors = schema.validate(load_fixture('invalid-dangling-relationship.json'))
    assert.is_false(ok)
    assert.truthy(has_error_containing(errors, 'references unknown id'))
  end)

  it('rejects duplicate entity ids', function()
    local ok, errors = schema.validate(load_fixture('invalid-duplicate-id.json'))
    assert.is_false(ok)
    assert.truthy(has_error_containing(errors, 'duplicate id'))
  end)

  it('rejects a non-table model', function()
    local ok, errors = schema.validate(nil)
    assert.is_false(ok)
    assert.equals(1, #errors)
  end)
end)
