-- walkthrough-nvim.persist.root — locate the repository a walkthrough
-- belongs to. Adapted from cartograph.nvim's root.lua (synchronous
-- marker-walk); simplified to a single marker since, unlike cartograph's
-- repo scan, this only needs a stable identity, not a language-specific
-- workspace boundary.

local M = {}

local MARKERS = { '.git' }

local function has_marker(dir)
  for _, marker in ipairs(MARKERS) do
    if vim.fn.isdirectory(dir .. '/' .. marker) == 1 or vim.fn.filereadable(dir .. '/' .. marker) == 1 then
      return true
    end
  end
  return false
end

--- Walk up from `start` (default: cwd) looking for a marker. Falls back to
--- `start` itself when no marker is found, so callers always get a usable
--- (if not strictly "correct") identity rather than nil.
function M.find(start)
  local dir = start or vim.fn.getcwd()
  local check = dir
  while true do
    if has_marker(check) then
      return check
    end
    local parent = vim.fn.fnamemodify(check, ':h')
    if parent == check then
      break
    end
    check = parent
  end
  return dir
end

return M
