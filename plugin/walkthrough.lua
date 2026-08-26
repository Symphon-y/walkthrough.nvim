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
