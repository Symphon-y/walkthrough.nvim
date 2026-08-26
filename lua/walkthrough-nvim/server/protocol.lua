-- walkthrough-nvim.server.protocol — pure browser->nvim action routing.
-- Adapted from cartograph.nvim's protocol.lua: the browser POSTs JSON
-- messages ({ action = ..., ...params }); this module validates them and
-- routes to an injected `engine` interface (server/bridge.lua). It knows
-- nothing about transport (server.lua) or how the engine fulfils a
-- request -- only the contract between them.
--
-- Phase 1 needs focus/reveal: a walkthrough model is small and curated up
-- front (unlike cartograph's incrementally-fetched-via-LSP graph), so
-- there is nothing to progressively "expand" -- the whole model renders
-- immediately, and clicking a node highlights it and its neighbors
-- (model/focus.lua's overlay) rather than fetching more nodes.
-- Phase 2 adds accept/challenge/correct -- the engineer's correction loop.

local M = {}

local unpack = table.unpack or unpack

-- action -> { engine method, required params (in call order) }.
local ROUTES = {
  focus = { method = 'focus', params = { 'nodeId' } },
  clearFocus = { method = 'clear_focus', params = {} },
  reveal = { method = 'reveal', params = { 'nodeId' } },
  revealAt = { method = 'reveal_at', params = { 'file', 'line' } },
  accept = { method = 'accept', params = { 'nodeId' } },
  challenge = { method = 'challenge', params = { 'nodeId' } },
  correct = { method = 'correct', params = { 'nodeId', 'note' } },
}

local function err(message)
  return { status = 'error', message = message }
end

-- Route a decoded message table to the engine. Returns { status = 'ok' } or
-- { status = 'error', message = ... }.
function M.dispatch(msg, engine)
  if type(msg) ~= 'table' or msg.action == nil then
    return err('missing action')
  end

  local route = ROUTES[msg.action]
  if not route then
    return err('unknown action: ' .. tostring(msg.action))
  end

  local args = {}
  for i, name in ipairs(route.params) do
    local value = msg[name]
    if value == nil then
      return err(('%s requires "%s"'):format(msg.action, name))
    end
    args[i] = value
  end

  local fn = engine[route.method]
  if type(fn) ~= 'function' then
    return err('engine cannot handle: ' .. msg.action)
  end
  fn(unpack(args, 1, #route.params))

  return { status = 'ok' }
end

-- Decode a raw JSON request body and dispatch it.
function M.handle(raw, engine)
  local ok, msg = pcall(vim.json.decode, raw)
  if not ok then
    return err('malformed JSON')
  end
  return M.dispatch(msg, engine)
end

return M
