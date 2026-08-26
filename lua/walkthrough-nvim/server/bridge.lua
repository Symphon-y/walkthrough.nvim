-- walkthrough-nvim.server.bridge — the engine interface server.lua and
-- protocol.lua talk to. Adapted from cartograph.nvim's bridge.lua:
-- translates browser actions into calls against ui/state's active
-- session, backed by the pure model/ modules.
--
-- snapshot (initial GET /api/model), focus (highlight a node + its
-- neighbors, dim the rest), clear_focus, reveal (jump to source), and the
-- correction loop: accept/challenge/correct mutate the current revision
-- in place (ui/correct.lua) and broadcast the updated model so every
-- connected browser reflects the new status live.

local M = {}

local state = require('walkthrough-nvim.ui.state')
local focus = require('walkthrough-nvim.model.focus')
local reveal = require('walkthrough-nvim.ui.reveal')
local correct_mod = require('walkthrough-nvim.ui.correct')

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
    diff = state.session.diff, -- present only after :WalkthroughDiff
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

--- Jump the editor directly to a file/line -- for evidence with no entity
--- id of its own (a data_lineage stage, a decision option).
function M.reveal_at(file, line)
  if not state.active() then
    return
  end
  reveal.reveal_at(file, line)
end

--- Push the whole current model to every connected browser -- used after
--- a correction changes an entity's status, since that's a data change,
--- not just a view-state change (focus:update is for the latter).
local function broadcast_model()
  if state.session.server then
    state.session.server:broadcast('model:update', { model = state.session.model })
  end
end

local function apply_correction(fn, ...)
  if not state.active() then
    return
  end
  local ok, err = fn(...)
  if ok then
    broadcast_model()
  else
    vim.notify('walkthrough: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.accept(node_id)
  apply_correction(correct_mod.accept, node_id)
end

function M.challenge(node_id)
  apply_correction(correct_mod.challenge, node_id)
end

function M.correct(node_id, note)
  apply_correction(correct_mod.correct, node_id, note)
end

return M
