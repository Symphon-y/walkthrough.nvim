-- walkthrough-nvim.server.http_wire — pure HTTP/1.1 wire-format helpers.
-- Adapted near-verbatim from cartograph.nvim's http_wire.lua: parsing a
-- request and building a response are kept free of any I/O or Neovim API
-- so they can be unit-tested in isolation; server.lua owns the actual
-- sockets and only borrows these to translate bytes <-> tables.

local M = {}

local STATUS_TEXT = {
  [200] = 'OK',
  [204] = 'No Content',
  [400] = 'Bad Request',
  [403] = 'Forbidden',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [500] = 'Internal Server Error',
}

local MIME = {
  html = 'text/html; charset=utf-8',
  htm = 'text/html; charset=utf-8',
  js = 'application/javascript',
  mjs = 'application/javascript',
  css = 'text/css',
  json = 'application/json',
  svg = 'image/svg+xml',
  png = 'image/png',
  ico = 'image/x-icon',
  map = 'application/json',
}

-- Decode a percent-encoded query component (also turns '+' into space).
function M.urldecode(s)
  s = s:gsub('+', ' ')
  return (s:gsub('%%(%x%x)', function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- Percent-encode a query component (RFC 3986 unreserved characters are left as-is).
function M.urlencode(s)
  s = tostring(s)
  return (s:gsub('[^%w%-_%.~]', function(c)
    return string.format('%%%02X', string.byte(c))
  end))
end

-- Parse a `k=v&k2=v2` query string into a (url-decoded) table.
function M.parse_query(qs)
  local out = {}
  if not qs or qs == '' then
    return out
  end
  for pair in qs:gmatch('[^&]+') do
    local k, v = pair:match('^([^=]+)=?(.*)$')
    if k then
      out[M.urldecode(k)] = M.urldecode(v)
    end
  end
  return out
end

function M.status_text(code)
  return STATUS_TEXT[code] or 'Unknown'
end

function M.mime_for(path)
  local ext = path:match('%.([%w]+)$')
  return ext and MIME[ext:lower()] or 'application/octet-stream'
end

-- Parse a complete raw HTTP request into { method, path, query, headers, body }.
-- Header names are lowercased. Returns nil on a malformed request line.
function M.parse_request(raw)
  local head, body = raw:match('^(.-)\r\n\r\n(.*)$')
  if not head then
    head, body = raw, ''
  end

  local lines = {}
  for line in (head .. '\r\n'):gmatch('(.-)\r\n') do
    lines[#lines + 1] = line
  end

  local request_line = lines[1] or ''
  local method, target = request_line:match('^(%u+)%s+(%S+)%s+HTTP/%d%.%d$')
  if not method then
    return nil
  end

  local path, qs = target:match('^([^?]*)%??(.*)$')

  local headers = {}
  for i = 2, #lines do
    local k, v = lines[i]:match('^([^:]+):%s*(.*)$')
    if k then
      headers[k:lower()] = v
    end
  end

  return {
    method = method,
    target = target,
    path = path,
    query = M.parse_query(qs),
    headers = headers,
    body = body or '',
  }
end

-- Content-Length header as a number (0 when absent/invalid).
function M.content_length(headers)
  return tonumber(headers and headers['content-length']) or 0
end

-- Build a complete HTTP response string from { status, headers, body }.
function M.build_response(opts)
  opts = opts or {}
  local status = opts.status or 200
  local body = opts.body or ''
  local headers = vim.deepcopy(opts.headers or {})

  if headers['Content-Length'] == nil then
    headers['Content-Length'] = tostring(#body)
  end
  if headers['Connection'] == nil then
    headers['Connection'] = 'close'
  end

  local lines = { ('HTTP/1.1 %d %s'):format(status, M.status_text(status)) }
  local names = {}
  for name in pairs(headers) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    lines[#lines + 1] = name .. ': ' .. headers[name]
  end

  return table.concat(lines, '\r\n') .. '\r\n\r\n' .. body
end

return M
