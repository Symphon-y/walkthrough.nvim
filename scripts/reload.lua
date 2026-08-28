-- Dev-loop helper: pull the latest commit and hot-reload this plugin's Lua
-- modules without restarting Neovim. Run with :source on this file.
--
-- require() caches modules, so pulling new code onto disk alone doesn't
-- change what a running session sees -- this clears every
-- walkthrough-nvim.* entry from package.loaded, then re-sources
-- plugin/walkthrough.lua (after resetting its vim.g.loaded_walkthrough
-- guard, or it would just no-op) to re-register every :Walkthrough*
-- command against the freshly-reloaded code.

local root = require('walkthrough-nvim.skills').plugin_root()

print('walkthrough-nvim: pulling ' .. root)
print(vim.fn.system({ 'git', '-C', root, 'pull' }))

for name in pairs(package.loaded) do
  if name:match('^walkthrough%-nvim') then
    package.loaded[name] = nil
  end
end

vim.g.loaded_walkthrough = nil
vim.cmd('source ' .. vim.fn.fnameescape(root .. '/plugin/walkthrough.lua'))

print('walkthrough-nvim: reloaded')
