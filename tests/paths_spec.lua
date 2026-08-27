local paths = require('walkthrough-nvim.persist.paths')
local schema = require('walkthrough-nvim.model.schema')

describe('walkthrough-nvim.persist.paths', function()
  before_each(function()
    require('walkthrough-nvim.config').setup({ data_dir = vim.fn.tempname() })
  end)

  describe('normalize_root', function()
    it('converts backslashes to forward slashes', function()
      assert.equals('C:/Users/Travi/repo', paths.normalize_root('C:\\Users\\Travi\\repo'))
    end)

    it('strips a trailing slash', function()
      assert.equals('C:/Users/Travi/repo', paths.normalize_root('C:/Users/Travi/repo/'))
    end)
  end)

  describe('repo_hash', function()
    it('is stable and 16 hex chars', function()
      local h = paths.repo_hash('C:/repo')
      assert.equals(16, #h)
      assert.truthy(h:match('^%x+$'))
    end)

    it('hashes the same regardless of slash style (Windows-safe)', function()
      local a = paths.repo_hash('C:\\Users\\Travi\\repo')
      local b = paths.repo_hash('C:/Users/Travi/repo')
      assert.equals(a, b)
    end)

    it('differs between different roots', function()
      assert.is_false(paths.repo_hash('C:/repo-a') == paths.repo_hash('C:/repo-b'))
    end)
  end)

  describe('assert_valid_slug', function()
    it('accepts alphanumeric, dash, underscore', function()
      assert.has_no.errors(function() paths.assert_valid_slug('checkout-refund_flow', 'id') end)
    end)

    it('rejects path traversal attempts', function()
      assert.has_error(function() paths.assert_valid_slug('../../etc', 'id') end)
      assert.has_error(function() paths.assert_valid_slug('a/b', 'id') end)
      assert.has_error(function() paths.assert_valid_slug('has spaces', 'id') end)
    end)
  end)

  describe('path composition', function()
    it('builds a walkthrough_dir under the repo hash', function()
      local dir = paths.walkthrough_dir('C:/repo', 'checkout-refund-flow')
      assert.truthy(dir:find(paths.repo_hash('C:/repo'), 1, true))
      assert.truthy(dir:find('checkout-refund-flow', 1, true))
    end)

    it('builds a revision_path ending in <revision_id>.json under revisions/', function()
      local p = paths.revision_path('C:/repo', 'checkout-refund-flow', 'expl-001')
      assert.truthy(p:find('revisions/expl%-001%.json$'))
    end)

    it('rejects an invalid revision_id even inside revision_path', function()
      assert.has_error(function()
        paths.revision_path('C:/repo', 'checkout-refund-flow', '../escape')
      end)
    end)
  end)

  describe('next_revision_id', function()
    it('starts at 001 for a brand-new (nil) manifest', function()
      assert.equals('expl-001', paths.next_revision_id(nil, schema.PHASE.EXPLORATION))
    end)

    it('increments from the highest existing id in that phase', function()
      local manifest = {
        revisions = {
          { id = 'expl-001', phase = 'exploration' },
          { id = 'expl-002', phase = 'exploration' },
        },
      }
      assert.equals('expl-003', paths.next_revision_id(manifest, schema.PHASE.EXPLORATION))
    end)

    it('tracks exploration, implementation, and proposal counters independently', function()
      local manifest = {
        revisions = {
          { id = 'expl-001', phase = 'exploration' },
          { id = 'expl-002', phase = 'exploration' },
          { id = 'impl-001', phase = 'implementation' },
          { id = 'prop-001', phase = 'proposal' },
        },
      }
      assert.equals('impl-002', paths.next_revision_id(manifest, schema.PHASE.IMPLEMENTATION))
      assert.equals('prop-002', paths.next_revision_id(manifest, schema.PHASE.PROPOSAL))
      assert.equals('expl-003', paths.next_revision_id(manifest, schema.PHASE.EXPLORATION))
    end)

    it('mints prop-001 for a brand-new proposal phase', function()
      assert.equals('prop-001', paths.next_revision_id(nil, schema.PHASE.PROPOSAL))
    end)

    it('errors on an invalid phase', function()
      assert.has_error(function() paths.next_revision_id(nil, 'bogus') end)
    end)
  end)
end)
