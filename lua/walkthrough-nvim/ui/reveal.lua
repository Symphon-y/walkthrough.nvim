-- walkthrough-nvim.ui.reveal — jump the editor to an entity's evidence.
-- Adapted from cartograph.nvim's reveal.lua; keyed off the walkthrough
-- model's evidence citations rather than a graph node's own file/range,
-- since a walkthrough entity's identity and its evidence are separate
-- (an entity can have zero, one, or several evidence entries).

local M = {}

--- Open the file cited by `entity_id`'s first evidence entry and place
--- the cursor on its line. No-op if the entity has no evidence (an
--- INFERRED/UNKNOWN claim may legitimately have none).
function M.reveal(model, entity_id)
  local corrections = require('walkthrough-nvim.model.corrections')
  local entity = corrections.find_entity(model, entity_id)
  if not entity then
    return
  end
  local evidence = entity.evidence and entity.evidence[1]
  if not evidence or not evidence.file or evidence.file == '' then
    return
  end

  local root = require('walkthrough-nvim.ui.state').session and require('walkthrough-nvim.ui.state').session.root
  local path = evidence.file
  if root and not path:match('^%a:[\\/]') and not path:match('^/') then
    path = root .. '/' .. path
  end

  vim.schedule(function()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    if evidence.line then
      pcall(vim.api.nvim_win_set_cursor, 0, { evidence.line, 0 })
      vim.cmd('normal! zz')
    end
  end)
end

return M
