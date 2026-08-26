local correct_mod = require('walkthrough-nvim.ui.correct')
local state = require('walkthrough-nvim.ui.state')
local io_mod = require('walkthrough-nvim.persist.io')
local schema = require('walkthrough-nvim.model.schema')
local config = require('walkthrough-nvim.config')

local function sample_model()
  return {
    schema_version = schema.SCHEMA_VERSION,
    walkthrough_id = 'checkout-refund-flow',
    revision_id = 'expl-001',
    phase = schema.PHASE.EXPLORATION,
    status = schema.REVISION_STATUS.DRAFT,
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
  }
end

describe('walkthrough-nvim.ui.correct', function()
  local scratch_dir
  local repo_root = 'C:/fake-repo'

  before_each(function()
    scratch_dir = vim.fn.tempname()
    config.setup({ data_dir = scratch_dir })
    state.new(repo_root, 'checkout-refund-flow', sample_model())
  end)

  after_each(function()
    state.clear()
    pcall(vim.fn.delete, scratch_dir, 'rf')
  end)

  it('errors when there is no active session', function()
    state.clear()
    local ok, err = correct_mod.accept('component:refund-service')
    assert.is_false(ok)
    assert.truthy(err)
  end)

  describe('accept', function()
    it('sets status to accepted and persists it', function()
      local ok = correct_mod.accept('component:refund-service')
      assert.is_true(ok)
      assert.equals('accepted', state.session.model.components[1].status)

      local read_ok, persisted = io_mod.read_revision(repo_root, 'checkout-refund-flow', 'expl-001')
      assert.is_true(read_ok)
      assert.equals('accepted', persisted.components[1].status)
    end)

    it('errors on an unknown entity id', function()
      local ok, err = correct_mod.accept('component:nope')
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)

  describe('challenge', function()
    it('sets status to challenged and records a correction with no note', function()
      local ok = correct_mod.challenge('component:refund-service')
      assert.is_true(ok)
      assert.equals('challenged', state.session.model.components[1].status)
      assert.equals(1, #state.session.model.corrections)
      assert.is_nil(state.session.model.corrections[1].engineer_note)
    end)
  end)

  describe('correct', function()
    it('sets status to corrected and records the engineer note', function()
      local ok = correct_mod.correct('component:refund-service', 'This is dead code; see RefundOrchestrator instead.')
      assert.is_true(ok)
      assert.equals('corrected', state.session.model.components[1].status)
      assert.equals('This is dead code; see RefundOrchestrator instead.', state.session.model.corrections[1].engineer_note)
    end)

    it('rejects an empty note', function()
      local ok, err = correct_mod.correct('component:refund-service', '')
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)
end)
