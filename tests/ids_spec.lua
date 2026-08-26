local ids = require('walkthrough-nvim.model.ids')

describe('walkthrough-nvim.model.ids', function()
  describe('slugify', function()
    it('lowercases and dashes non-alphanumeric runs', function()
      assert.equals('refund-service', ids.slugify('RefundService'))
      assert.equals('refund-service', ids.slugify('Refund Service'))
      assert.equals('a-b-c', ids.slugify('A/B_C'))
    end)

    it('trims leading and trailing dashes', function()
      assert.equals('x', ids.slugify('  x  '))
    end)

    it('falls back to "unnamed" for empty input', function()
      assert.equals('unnamed', ids.slugify(''))
      assert.equals('unnamed', ids.slugify(nil))
    end)
  end)

  describe('collect', function()
    it('gathers ids across every entity collection', function()
      local model = {
        groups = { { id = 'group:domain' } },
        components = { { id = 'component:a' } },
        relationships = { { id = 'rel:a-b' } },
        decisions = { { id = 'decision:x' } },
        assumptions = { { id = 'assumption:y' } },
      }
      local collected = ids.collect(model)
      assert.is_true(collected['group:domain'])
      assert.is_true(collected['component:a'])
      assert.is_true(collected['rel:a-b'])
      assert.is_true(collected['decision:x'])
      assert.is_true(collected['assumption:y'])
    end)
  end)

  describe('mint', function()
    it('mints a kind-prefixed slug when there is no collision', function()
      local model = { components = {} }
      assert.equals('component:refund-service', ids.mint(model, 'component', 'RefundService'))
    end)

    it('disambiguates on collision by appending -2, -3, ...', function()
      local model = {
        components = {
          { id = 'component:refund-service' },
          { id = 'component:refund-service-2' },
        },
      }
      assert.equals('component:refund-service-3', ids.mint(model, 'component', 'RefundService'))
    end)
  end)
end)
