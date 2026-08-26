-- walkthrough-nvim.server.server — the local bridge: a minimal vim.uv
-- HTTP/SSE server. Adapted from cartograph.nvim's server.lua.
--
-- Thin transport only. It accepts loopback connections, hands raw bytes
-- to http_wire for parsing, gates data endpoints on a per-session token,
-- serves the bundled web UI, streams model updates via the sse hub, and
-- routes browser POSTs through protocol to the injected engine. All
-- wire-format, SSE and routing *logic* lives in the pure modules this
-- composes, which are unit-tested.
--
-- One deliberate departure from cartograph: GET /api/model serves the
-- current model as a plain JSON snapshot, fetched by the browser on first
-- paint. cartograph relies on the browser's SSE connection already being
-- open by the time the first `graph:update` broadcasts -- true there
-- because LSP-driven graph population takes long enough in practice for
-- the browser to have connected, but that's an implicit timing
-- assumption, not a guarantee. A walkthrough model is loaded from disk
-- and ready to serve near-instantly, so that assumption would not hold
-- here; fetch-then-subscribe avoids the race outright.

local M = {}

local uv = vim.uv or vim.loop
local wire = require('walkthrough-nvim.server.http_wire')
local sse = require('walkthrough-nvim.server.sse')
local protocol = require('walkthrough-nvim.server.protocol')

-- Locate the bundled web/ directory (this file is lua/walkthrough-nvim/server/server.lua).
local function web_dir()
  local src = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(src, ':h:h:h:h') .. '/web'
end

local function read_file(path)
  local fd = io.open(path, 'rb')
  if not fd then
    return nil
  end
  local content = fd:read('*a')
  fd:close()
  return content
end

-- A short, URL-safe per-session token so no other local process can connect.
local function make_token()
  local bytes = { ('%08x'):format(os.time()), ('%08x'):format(math.random(0, 0xffffff)) }
  if uv.random then
    local ok, rnd = pcall(uv.random, 8)
    if ok and rnd then
      bytes = { (rnd:gsub('.', function(c) return ('%02x'):format(c:byte()) end)) }
    end
  end
  return table.concat(bytes)
end

local Server = {}
Server.__index = Server

-- Write a full response, then close the socket once the write has drained.
-- Closing must wait for the write callback: uv_close cancels pending
-- writes, so closing eagerly truncates large bodies.
local function respond(client, status, content_type, body)
  if client:is_closing() then
    return
  end
  local payload = wire.build_response({
    status = status,
    headers = { ['Content-Type'] = content_type },
    body = body or '',
  })
  client:write(payload, function()
    if not client:is_closing() then
      client:close()
    end
  end)
end

-- Serve a file from web/, guarding against path traversal.
function Server:serve_static(client, path)
  if path == '/' then
    path = '/index.html'
  end
  if path:find('%.%.') then
    return respond(client, 403, 'text/plain', 'forbidden')
  end
  local body = read_file(web_dir() .. path)
  if not body then
    return respond(client, 404, 'text/plain', 'not found')
  end
  respond(client, 200, wire.mime_for(path), body)
end

function Server:authorized(req)
  if not self.token then
    return true
  end
  return req.query.token == self.token
end

-- Wrap a uv handle as an sse hub client (write(self, str) -> boolean).
local function sse_client(handle)
  return {
    handle = handle,
    write = function(self, payload)
      if self.handle:is_closing() then
        return false
      end
      local ok = pcall(function()
        self.handle:write(payload)
      end)
      return ok
    end,
  }
end

-- Route a request. Returns the sse client wrapper when it upgraded the
-- socket to a long-lived SSE stream (so the caller keeps it open), nil otherwise.
function Server:route(req, client)
  -- Initial snapshot -- token-gated.
  if req.method == 'GET' and req.path == '/api/model' then
    if not self:authorized(req) then
      return respond(client, 403, 'application/json', vim.json.encode({ status = 'error', message = 'forbidden' }))
    end
    local ok, model = pcall(self.engine.snapshot)
    if not ok or model == nil then
      return respond(client, 404, 'application/json', vim.json.encode({ status = 'error', message = 'no active model' }))
    end
    return respond(client, 200, 'application/json', vim.json.encode(model))
  end

  -- SSE stream — long-lived, token-gated.
  if req.method == 'GET' and req.path == '/events' then
    if not self:authorized(req) then
      respond(client, 403, 'text/plain', 'forbidden')
      return nil
    end
    client:write(sse.headers())
    local sc = sse_client(client)
    self.hub:add(sc)
    self.hub:broadcast('status', { connected = true })
    return sc -- keep the socket open
  end

  -- Browser -> nvim messages — token-gated.
  if req.method == 'POST' and req.path == '/api/message' then
    if not self:authorized(req) then
      return respond(client, 403, 'application/json', vim.json.encode({ status = 'error', message = 'forbidden' }))
    end
    local result = protocol.handle(req.body, self.engine)
    local status = result.status == 'ok' and 200 or 400
    respond(client, status, 'application/json', vim.json.encode(result))
    return
  end

  -- Everything else is a static asset (the UI shell is not sensitive).
  if req.method == 'GET' then
    return self:serve_static(client, req.path)
  end

  respond(client, 405, 'text/plain', 'method not allowed')
end

function Server:on_connection()
  local client = uv.new_tcp()
  self.tcp:accept(client)

  local buf = ''
  local handled = false
  local sse_ref = nil

  local function close()
    if sse_ref then
      self.hub:remove(sse_ref)
    end
    if not client:is_closing() then
      client:close()
    end
  end

  client:read_start(function(err, chunk)
    if err or not chunk then
      return close()
    end

    buf = buf .. chunk
    if handled or not buf:find('\r\n\r\n', 1, true) then
      return
    end

    local req = wire.parse_request(buf)
    if not req then
      handled = true
      return vim.schedule(function()
        respond(client, 400, 'text/plain', 'bad request')
      end)
    end

    if req.method == 'POST' and #req.body < wire.content_length(req.headers) then
      return
    end

    handled = true
    vim.schedule(function()
      sse_ref = self:route(req, client)
    end)
  end)
end

-- Push an event to every connected browser.
function Server:broadcast(event, data)
  self.hub:broadcast(event, data)
end

function Server:stop()
  self.hub:close_all()
  if self.tcp and not self.tcp:is_closing() then
    self.tcp:close()
  end
  self.tcp = nil
end

-- Start a server. opts = { host, port, token = bool, engine = <interface> }.
-- engine must provide: snapshot(), expand(nodeId), reveal(nodeId).
function M.start(opts)
  opts = opts or {}
  local self = setmetatable({
    engine = opts.engine or {},
    hub = sse.new_hub(),
    token = opts.token ~= false and make_token() or nil,
  }, Server)

  self.tcp = uv.new_tcp()
  local ok, err = pcall(function()
    assert(self.tcp:bind(opts.host or '127.0.0.1', opts.port or 0))
    self.tcp:listen(128, function(listen_err)
      if not listen_err then
        self:on_connection()
      end
    end)
  end)
  if not ok then
    self:stop()
    error('walkthrough: could not start server: ' .. tostring(err))
  end

  local sock = self.tcp:getsockname()
  self.host = sock.ip
  self.port = sock.port
  return self
end

-- Pure URL builder: host:port + path + a query of (token first, then
-- params sorted by key).
function M.build_url(opts)
  local query = {}
  local enc = wire.urlencode
  if opts.token and opts.token ~= '' then
    query[#query + 1] = 'token=' .. enc(opts.token)
  end
  local params = opts.params or {}
  local keys = {}
  for k in pairs(params) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    query[#query + 1] = enc(k) .. '=' .. enc(tostring(params[k]))
  end

  local url = ('http://%s:%d%s'):format(opts.host, opts.port, opts.path or '/')
  if #query > 0 then
    url = url .. '?' .. table.concat(query, '&')
  end
  return url
end

function Server:url(path, params)
  return M.build_url({
    host = self.host,
    port = self.port,
    token = self.token,
    path = path or '/',
    params = params,
  })
end

return M
