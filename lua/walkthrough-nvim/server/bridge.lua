-- walkthrough-nvim.server.bridge — the engine interface server.lua and
-- protocol.lua talk to. Adapted from cartograph.nvim's bridge.lua:
-- translates browser actions into calls against ui/state's active
-- session, backed by the pure model/ modules.
--
-- Phase 1 surface: snapshot (initial GET /api/model), focus (highlight a
-- node + its neighbors, dim the rest), clear_focus, reveal (jump to
-- source). Correct/challenge/accept land in Phase 2 as more methods on
-- this same table.

local M = {}

local state = require('walkthrough-nvim.ui.state')
local focus = require('walkthrough-nvim.model.focus')
local reveal = require('walkthrough-nvim.ui.reveal')

--- The current model, for the browser's initial GET /api/model fetch.
--- Includes the active focus path so a reconnecting browser (e.g. a page
--- refresh) resumes with the same node highlighted rather than resetting.
function M.snapshot()
  if not state.active() then
    return nil
  end
  return {
    model = state.session.model,
    focus = focus.overlay(state.session.model, state.session.focus_path or {}),
  }
end

--- Focus a node: extend the breadcrumb path and push the resulting
--- active/dimmed overlay to every connected browser.
function M.focus(node_id)
  if not state.active() then
    return
  end
  state.session.focus_path = focus.step(state.session.focus_path or {}, node_id)
  local overlay = focus.overlay(state.session.model, state.session.focus_path)
  if state.session.server then
    state.session.server:broadcast('focus:update', overlay)
  end
end

--- Clear the focus overlay (un-dim everything).
function M.clear_focus()
  if not state.active() then
    return
  end
  state.session.focus_path = {}
  if state.session.server then
    state.session.server:broadcast('focus:update', { active = vim.empty_dict(), dimmed = vim.empty_dict() })
  end
end

--- Jump the editor to the entity's cited source.
function M.reveal(node_id)
  if not state.active() then
    return
  end
  reveal.reveal(state.session.model, node_id)
end

return M
