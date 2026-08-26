-- walkthrough-nvim.ui.reveal — jump the editor to a cited evidence
-- location. Adapted from cartograph.nvim's reveal.lua; keyed off the
-- walkthrough model's evidence citations rather than a graph node's own
-- file/range, since a walkthrough entity's identity and its evidence are
-- separate (an entity can have zero, one, or several evidence entries).

local M = {}

--- Open `file` (resolved relative to the active session's repo root when
--- it isn't already absolute) and place the cursor on `line`.
function M.reveal_at(file, line)
  if not file or file == '' then
    return
  end

  local root = require('walkthrough-nvim.ui.state').session and require('walkthrough-nvim.ui.state').session.root
  local path = file
  if root and not path:match('^%a:[\\/]') and not path:match('^/') then
    path = root .. '/' .. path
  end

  vim.schedule(function()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    -- vim.json.decode turns JSON null into vim.NIL (truthy in Lua), not
    -- nil -- guard with an explicit type check rather than `if line`.
    if type(line) == 'number' and line >= 1 then
      pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
      vim.cmd('normal! zz')
    end
  end)
end

--- Open the file cited by `entity_id`'s first evidence entry. Works for
--- anything model/corrections.find_entity can locate (components,
--- relationships, decisions, assumptions, ...) -- not for a data_lineage
--- stage or a decision option, which have no id of their own; those go
--- through reveal_at() directly with the evidence the client already has.
--- No-op if the entity has no evidence (an INFERRED/UNKNOWN claim may
--- legitimately have none).
function M.reveal(model, entity_id)
  local corrections = require('walkthrough-nvim.model.corrections')
  local entity = corrections.find_entity(model, entity_id)
  if not entity then
    return
  end
  local evidence = entity.evidence and entity.evidence[1]
  if not evidence then
    return
  end
  M.reveal_at(evidence.file, evidence.line)
end

return M
