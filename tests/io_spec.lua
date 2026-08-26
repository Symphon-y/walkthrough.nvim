local io_mod = require('walkthrough-nvim.persist.io')
local paths = require('walkthrough-nvim.persist.paths')
local schema = require('walkthrough-nvim.model.schema')
local config = require('walkthrough-nvim.config')

local function sample_model(overrides)
  local model = {
    schema_version = schema.SCHEMA_VERSION,
    walkthrough_id = 'checkout-refund-flow',
    revision_id = 'expl-001',
    phase = schema.PHASE.EXPLORATION,
    status = schema.REVISION_STATUS.DRAFT,
    created_by = 'claude',
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
  return vim.tbl_deep_extend('force', model, overrides or {})
end

describe('walkthrough-nvim.persist.io', function()
  local scratch_dir
  local repo_root = 'C:/fake-repo'

  before_each(function()
    scratch_dir = vim.fn.tempname()
    config.setup({ data_dir = scratch_dir })
  end)

  after_each(function()
    pcall(vim.fn.delete, scratch_dir, 'rf')
  end)

  describe('write_json_atomic / read_json', function()
    it('round-trips a table through JSON', function()
      local path = scratch_dir .. '/x.json'
      local ok = io_mod.write_json_atomic(path, { a = 1, b = { 'x', 'y' } })
      assert.is_true(ok)
      local read_ok, data = io_mod.read_json(path)
      assert.is_true(read_ok)
      assert.equals(1, data.a)
      assert.same({ 'x', 'y' }, data.b)
    end)

    it('overwrites an existing file (Windows-safe rename)', function()
      local path = scratch_dir .. '/x.json'
      io_mod.write_json_atomic(path, { v = 1 })
      io_mod.write_json_atomic(path, { v = 2 })
      local _, data = io_mod.read_json(path)
      assert.equals(2, data.v)
    end)

    it('reports failure reading a nonexistent file', function()
      local ok, err = io_mod.read_json(scratch_dir .. '/nope.json')
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)

  describe('write_repo_identity', function()
    it('writes repo_root, normalized', function()
      io_mod.write_repo_identity('C:\\fake-repo')
      local ok, data = io_mod.read_json(paths.repo_identity_path('C:\\fake-repo'))
      assert.is_true(ok)
      assert.equals('C:/fake-repo', data.repo_root)
    end)

    it('is safe to call twice', function()
      io_mod.write_repo_identity(repo_root)
      assert.has_no.errors(function() io_mod.write_repo_identity(repo_root) end)
    end)
  end)

  describe('read_manifest', function()
    it('returns a fresh empty manifest when none exists yet', function()
      local m = io_mod.read_manifest(repo_root, 'checkout-refund-flow')
      assert.equals('checkout-refund-flow', m.walkthrough_id)
      assert.same({}, m.revisions)
    end)
  end)

  describe('write_revision / read_revision', function()
    it('writes a valid revision and it round-trips', function()
      local ok, err = io_mod.write_revision(repo_root, sample_model())
      assert.is_true(ok, err)

      local read_ok, model = io_mod.read_revision(repo_root, 'checkout-refund-flow', 'expl-001')
      assert.is_true(read_ok)
      assert.equals('RefundService', model.components[1].name)
    end)

    it('advances manifest.current[phase] and appends to manifest.revisions', function()
      io_mod.write_revision(repo_root, sample_model())
      local manifest = io_mod.read_manifest(repo_root, 'checkout-refund-flow')
      assert.equals('expl-001', manifest.current.exploration)
      assert.equals(1, #manifest.revisions)
      assert.equals('expl-001', manifest.revisions[1].id)
    end)

    it('rejects an invalid model and writes nothing', function()
      local invalid = sample_model({ status = 'not-a-real-status' })
      local ok, err = io_mod.write_revision(repo_root, invalid)
      assert.is_false(ok)
      assert.truthy(err)
      local read_ok = io_mod.read_revision(repo_root, 'checkout-refund-flow', 'expl-001')
      assert.is_false(read_ok)
    end)

    it('updates an already-listed manifest entry in place rather than duplicating it', function()
      io_mod.write_revision(repo_root, sample_model())
      io_mod.write_revision(repo_root, sample_model({ status = schema.REVISION_STATUS.CORRECTED }))
      local manifest = io_mod.read_manifest(repo_root, 'checkout-refund-flow')
      assert.equals(1, #manifest.revisions)
      assert.equals('corrected', manifest.revisions[1].status)
    end)
  end)

  describe('next_revision_path', function()
    it('starts a brand-new walkthrough at <phase>-001', function()
      local p = io_mod.next_revision_path(repo_root, 'checkout-refund-flow', schema.PHASE.EXPLORATION)
      assert.truthy(p:find('expl%-001%.json$'))
    end)

    it('advances after a revision is actually written', function()
      io_mod.write_revision(repo_root, sample_model())
      local p = io_mod.next_revision_path(repo_root, 'checkout-refund-flow', schema.PHASE.EXPLORATION)
      assert.truthy(p:find('expl%-002%.json$'))
    end)
  end)

  describe('list_walkthroughs', function()
    it('lists every walkthrough_id with a manifest under this repo, sorted', function()
      io_mod.write_revision(repo_root, sample_model({ walkthrough_id = 'zzz-flow', revision_id = 'expl-001' }))
      io_mod.write_revision(repo_root, sample_model({ walkthrough_id = 'aaa-flow', revision_id = 'expl-001' }))
      assert.same({ 'aaa-flow', 'zzz-flow' }, io_mod.list_walkthroughs(repo_root))
    end)
  end)
end)
