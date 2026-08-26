-- walkthrough-nvim.server.browser — open a URL in the user's default
-- browser. Copied verbatim from cartograph.nvim's browser.lua.

local M = {}

function M.open(url)
  local cmd
  if vim.fn.has('mac') == 1 then
    cmd = { 'open', url }
  elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    -- The empty string is the window title; required when the URL contains & or ?
    cmd = { 'cmd', '/c', 'start', '', url }
  else
    cmd = { 'xdg-open', url }
  end
  vim.fn.jobstart(cmd, { detach = true })
end

return M
