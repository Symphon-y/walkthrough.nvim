local focus = require('walkthrough-nvim.model.focus')

local function sample_model()
  return {
    groups = { { id = 'group:domain', name = 'Domain' } },
    components = {
      { id = 'component:a', group = 'group:domain' },
      { id = 'component:b', group = 'group:domain' },
      { id = 'component:c' },
    },
    relationships = {
      { id = 'rel:a-b', from = 'component:a', to = 'component:b' },
      { id = 'rel:b-c', from = 'component:b', to = 'component:c' },
    },
  }
end

describe('walkthrough-nvim.model.focus', function()
  describe('neighbors', function()
    it('includes the other end of every relationship touching the id, plus its group', function()
      local n = focus.neighbors(sample_model(), 'component:a')
      assert.same({ 'component:b', 'rel:a-b', 'group:domain' }, n)
    end)

    it('includes group members when focused on the group itself', function()
      local n = focus.neighbors(sample_model(), 'group:domain')
      assert.same({ 'component:a', 'component:b' }, n)
    end)

    it('returns an empty list for an isolated id', function()
      local n = focus.neighbors({ components = { { id = 'component:z' } } }, 'component:z')
      assert.same({}, n)
    end)
  end)

  describe('expand', function()
    it('adds the id and its neighbors without mutating the input set', function()
      local model = sample_model()
      local original = {}
      local expanded = focus.expand(model, original, 'component:a')

      assert.same({}, original)
      assert.is_true(expanded['component:a'])
      assert.is_true(expanded['component:b'])
      assert.is_true(expanded['rel:a-b'])
      assert.is_true(expanded['group:domain'])
      assert.is_nil(expanded['component:c'])
    end)

    it('accumulates across successive expansions', function()
      local model = sample_model()
      local set = focus.expand(model, {}, 'component:a')
      set = focus.expand(model, set, 'component:c')
      assert.is_true(set['component:a'])
      assert.is_true(set['component:c'])
      assert.is_true(set['rel:b-c'])
    end)
  end)

  describe('step', function()
    it('appends without mutating the input path', function()
      local path = { 'component:a' }
      local next_path = focus.step(path, 'component:b')
      assert.same({ 'component:a' }, path)
      assert.same({ 'component:a', 'component:b' }, next_path)
    end)
  end)

  describe('overlay', function()
    it('marks the path and the last step neighbors as active, everything else dimmed', function()
      local model = sample_model()
      local overlay = focus.overlay(model, { 'component:a' })

      assert.is_true(overlay.active['component:a'])
      assert.is_true(overlay.active['component:b'])
      assert.is_true(overlay.active['rel:a-b'])
      assert.is_true(overlay.active['group:domain'])

      assert.is_true(overlay.dimmed['component:c'])
      assert.is_true(overlay.dimmed['rel:b-c'])
      assert.is_nil(overlay.dimmed['component:a'])
    end)

    it('dims everything when given an empty path', function()
      local model = sample_model()
      local overlay = focus.overlay(model, {})
      assert.is_true(overlay.dimmed['component:a'])
      assert.is_true(overlay.dimmed['component:b'])
      assert.is_true(overlay.dimmed['component:c'])
      assert.same({}, overlay.active)
    end)
  end)
end)
