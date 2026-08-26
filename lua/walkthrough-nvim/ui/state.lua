-- walkthrough-nvim.ui.state — runtime session state for the active
-- walkthrough. Adapted from cartograph.nvim's state.lua: the engine
-- (server/bridge.lua) and the server share this as one source of truth.

local M = {}

M.session = nil

--- Create a fresh session for the given repo/walkthrough/model and make
--- it the active one. Any previous session's server is left running --
--- callers that want a clean switch should call M.session.server:stop()
--- first (init.lua's M.open() does this).
--
-- `diff` (optional): { before_id, after_id, result } from model/diff.lua,
-- set only by :WalkthroughDiff -- `model` is still the after-model, so
-- every normal view (architecture/sequence/lineage/decisions) renders it
-- as usual; `diff` additionally unlocks the before/after delta view.
function M.new(root, walkthrough_id, model, diff)
  M.session = {
    root = root,
    walkthrough_id = walkthrough_id,
    model = model,
    diff = diff,
    focus_path = {}, -- breadcrumb path for model/focus.lua's overlay
    server = nil, -- set once server.start() succeeds
  }
  return M.session
end

function M.active()
  return M.session ~= nil
end

function M.clear()
  if M.session and M.session.server then
    M.session.server:stop()
  end
  M.session = nil
end

return M
