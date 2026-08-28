if vim.g.loaded_walkthrough == 1 then
  return
end
vim.g.loaded_walkthrough = 1

vim.api.nvim_create_user_command('WalkthroughValidate', function(cmd_opts)
  local path = cmd_opts.args
  if path == '' then
    vim.notify('walkthrough: usage :WalkthroughValidate {path}', vim.log.levels.ERROR)
    return
  end
  require('walkthrough-nvim').validate(path)
end, { nargs = '?', complete = 'file', desc = 'Validate a walkthrough revision JSON file against the schema' })

vim.api.nvim_create_user_command('WalkthroughOpen', function(cmd_opts)
  require('walkthrough-nvim').open(cmd_opts.args)
end, { nargs = '?', desc = 'Open a walkthrough\'s current exploration revision' })

vim.api.nvim_create_user_command('WalkthroughClose', function()
  require('walkthrough-nvim').close()
end, { desc = 'Close the active walkthrough session' })

vim.api.nvim_create_user_command('WalkthroughHistory', function(cmd_opts)
  require('walkthrough-nvim').history(cmd_opts.args)
end, { nargs = '?', desc = 'Pick a past revision of a walkthrough and open it' })

vim.api.nvim_create_user_command('WalkthroughLoad', function(cmd_opts)
  local id, revision_id = cmd_opts.args:match('^(%S+)%s+(%S+)$')
  require('walkthrough-nvim').load(id, revision_id)
end, { nargs = '?', desc = 'Open a specific revision: :WalkthroughLoad {walkthrough_id} {revision_id}' })

vim.api.nvim_create_user_command('WalkthroughDiff', function(cmd_opts)
  require('walkthrough-nvim').diff(cmd_opts.fargs[1], cmd_opts.fargs[2], cmd_opts.fargs[3])
end, {
  nargs = '*',
  desc = 'Open a before/after diff: :WalkthroughDiff {id} [before-phase] [after-phase] (default exploration/implementation)',
})

vim.api.nvim_create_user_command('WalkthroughSetup', function(cmd_opts)
  require('walkthrough-nvim').setup_skills(cmd_opts.bang)
end, {
  bang = true,
  desc = 'Install/repair this plugin\'s Claude Code skills into ~/.claude/skills (! to overwrite conflicts)',
})
