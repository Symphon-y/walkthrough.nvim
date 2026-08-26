local M = {}

local defaults = {
  -- Overrides where walkthrough state is stored (default: stdpath('data')).
  -- Mainly for tests, but a real escape hatch too (e.g. a shared data dir).
  data_dir = nil,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

return M
