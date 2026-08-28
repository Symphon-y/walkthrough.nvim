-- walkthrough-nvim.health — :checkhealth walkthrough-nvim. Currently just
-- reports each Claude Code skill's install status under ~/.claude/skills/
-- (see skills.lua) -- a thin presentation layer over data skills.lua
-- already computes, no new logic here.

local M = {}

function M.check()
  vim.health.start('walkthrough-nvim: Claude Code skills')

  local ok, skills = pcall(require, 'walkthrough-nvim.skills')
  if not ok then
    vim.health.error('could not load walkthrough-nvim.skills: ' .. tostring(skills))
    return
  end

  local status_ok, status = pcall(skills.status)
  if not status_ok then
    vim.health.error('could not read skill status: ' .. tostring(status))
    return
  end

  local names = {}
  for name in pairs(status) do
    names[#names + 1] = name
  end
  table.sort(names)

  if #names == 0 then
    vim.health.warn('no skills found under ' .. skills.source_dir())
    return
  end

  for _, name in ipairs(names) do
    local entry = status[name]
    if entry.state == 'linked' then
      vim.health.ok(name .. ': linked -> ' .. entry.source)
    elseif entry.state == 'missing' then
      vim.health.warn(name .. ': not installed at ' .. entry.target, { 'run :WalkthroughSetup' })
    elseif entry.state == 'stale_link' then
      vim.health.warn(name .. ': linked to a stale path', { 'run :WalkthroughSetup to repoint it' })
    elseif entry.state == 'conflict' then
      vim.health.error(
        name .. ': ' .. entry.target .. ' exists and is not managed by this plugin',
        { 'run :WalkthroughSetup! to overwrite it, or remove it manually' }
      )
    end
  end
end

return M
