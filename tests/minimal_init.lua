local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
local root = vim.fn.fnamemodify(here, ':h')

vim.opt.runtimepath:prepend(root)
package.path = root .. '/?.lua;' .. package.path

local plenary_candidates = {
  root .. '/.deps/plenary.nvim',
  vim.fn.fnamemodify(root, ':h') .. '/plenary.nvim',
}
for _, p in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:append(p)
    break
  end
end

vim.cmd('runtime plugin/plenary.vim')
