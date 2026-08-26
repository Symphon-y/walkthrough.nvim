-- One-shot diagnostic: where does this Neovim session think the repo
-- root and manifest for "smoke-test-2" are, and does anything actually
-- exist there? Run with :source on this file.

local paths = require('walkthrough-nvim.persist.paths')
local root_mod = require('walkthrough-nvim.persist.root')
local io_mod = require('walkthrough-nvim.persist.io')

print('cwd:', vim.fn.getcwd())
print('current buffer:', vim.api.nvim_buf_get_name(0))

local root = root_mod.find()
print('resolved root:', root)
print('repo hash:', paths.repo_hash(root))
print('repo dir:', paths.repo_dir(root))
print('repo dir exists:', vim.fn.isdirectory(paths.repo_dir(root)) == 1)

local manifest_path = paths.manifest_path(root, 'smoke-test-2')
print('manifest path:', manifest_path)
print('manifest file exists:', vim.fn.filereadable(manifest_path) == 1)

local manifest = io_mod.read_manifest(root, 'smoke-test-2')
print('revisions found:', #(manifest.revisions or {}))
print(vim.inspect(manifest))
