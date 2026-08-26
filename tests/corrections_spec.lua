local corrections = require('walkthrough-nvim.model.corrections')

local function sample_model()
  return {
    components = {
      {
        id = 'component:refund-service',
        name = 'RefundService',
        claim_type = 'OBSERVED',
        confidence = 'high',
        evidence = { { file = 'src/refunds/RefundService.cs', line = 42 } },
        status = 'proposed',
      },
    },
    corrections = {},
  }
end

describe('walkthrough-nvim.model.corrections', function()
  describe('find_entity', function()
    it('finds a component by id and returns its collection', function()
      local model = sample_model()
      local entity, collection = corrections.find_entity(model, 'component:refund-service')
      assert.equals('RefundService', entity.name)
      assert.equals('components', collection)
    end)

    it('returns nil for an unknown id', function()
      local entity = corrections.find_entity(sample_model(), 'component:nope')
      assert.is_nil(entity)
    end)
  end)

  describe('set_status', function()
    it('updates an entity status in place', function()
      local model = sample_model()
      local ok = corrections.set_status(model, 'component:refund-service', 'accepted')
      assert.is_true(ok)
      assert.equals('accepted', model.components[1].status)
    end)

    it('errors on an unknown id', function()
      local ok, err = corrections.set_status(sample_model(), 'component:nope', 'accepted')
      assert.is_false(ok)
      assert.truthy(err)
    end)

    it('asserts on an invalid status value', function()
      assert.has_error(function()
        corrections.set_status(sample_model(), 'component:refund-service', 'bogus')
      end)
    end)
  end)

  describe('add_correction', function()
    it('moves the target to "corrected" when an engineer_note is supplied', function()
      local model = sample_model()
      local record = corrections.add_correction(model, {
        target = 'component:refund-service',
        kind = 'outdated',
        engineer_note = 'RefundService is dead code; real path is RefundOrchestrator.',
      })
      assert.equals('correction:0001', record.id)
      assert.equals('corrected', model.components[1].status)
      assert.equals(1, #model.corrections)
      assert.is_false(model.corrections[1].resolved)
    end)

    it('moves the target to "challenged" when no engineer_note is supplied', function()
      local model = sample_model()
      corrections.add_correction(model, { target = 'component:refund-service' })
      assert.equals('challenged', model.components[1].status)
    end)

    it('mints sequential correction ids', function()
      local model = sample_model()
      corrections.add_correction(model, { target = 'component:refund-service' })
      local second = corrections.add_correction(model, { target = 'component:refund-service' })
      assert.equals('correction:0002', second.id)
    end)

    it('errors when the target id is unknown', function()
      local record, err = corrections.add_correction(sample_model(), { target = 'component:nope' })
      assert.is_nil(record)
      assert.truthy(err)
    end)
  end)

  describe('resolve_correction / open_corrections', function()
    it('tracks which corrections are still open', function()
      local model = sample_model()
      local record = corrections.add_correction(model, { target = 'component:refund-service' })
      assert.equals(1, #corrections.open_corrections(model))

      local ok = corrections.resolve_correction(model, record.id, 'expl-002')
      assert.is_true(ok)
      assert.equals(0, #corrections.open_corrections(model))
      assert.equals('expl-002', model.corrections[1].resolved_in_revision)
    end)

    it('errors resolving an unknown correction id', function()
      local ok, err = corrections.resolve_correction(sample_model(), 'correction:9999', 'expl-002')
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)
end)
