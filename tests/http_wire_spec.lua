local wire = require('walkthrough-nvim.server.http_wire')

describe('walkthrough-nvim.server.http_wire', function()
  describe('parse_request', function()
    it('parses method, path, query and headers', function()
      local raw = table.concat({
        'GET /api/model?token=abc123 HTTP/1.1',
        'Host: 127.0.0.1',
        '',
        '',
      }, '\r\n')
      local req = wire.parse_request(raw)
      assert.are.equal('GET', req.method)
      assert.are.equal('/api/model', req.path)
      assert.are.equal('abc123', req.query.token)
      assert.are.equal('127.0.0.1', req.headers.host) -- header names lowercased
    end)

    it('parses a POST body', function()
      local body = '{"action":"reveal","nodeId":"component:x"}'
      local raw = table.concat({
        'POST /api/message HTTP/1.1',
        'Content-Type: application/json',
        'Content-Length: ' .. #body,
        '',
        body,
      }, '\r\n')
      local req = wire.parse_request(raw)
      assert.are.equal('POST', req.method)
      assert.are.equal(body, req.body)
      assert.are.equal(tostring(#body), req.headers['content-length'])
    end)

    it('returns nil on a malformed request line', function()
      assert.is_nil((wire.parse_request('not a real request\r\n\r\n')))
    end)
  end)

  it('reports the declared content length', function()
    assert.are.equal(42, wire.content_length({ ['content-length'] = '42' }))
    assert.are.equal(0, wire.content_length({}))
  end)

  describe('build_response', function()
    it('builds a well-formed response with headers and body', function()
      local res = wire.build_response({
        status = 200,
        headers = { ['Content-Type'] = 'text/plain' },
        body = 'hi',
      })
      assert.is_truthy(res:match('^HTTP/1%.1 200 OK\r\n'))
      assert.is_truthy(res:find('Content%-Type: text/plain'))
      assert.is_truthy(res:find('Content%-Length: 2'))
      assert.is_truthy(res:match('\r\n\r\nhi$'))
    end)
  end)

  it('maps file extensions to mime types', function()
    assert.are.equal('text/html; charset=utf-8', wire.mime_for('/index.html'))
    assert.are.equal('application/javascript', wire.mime_for('/app.js'))
    assert.are.equal('text/css', wire.mime_for('/styles.css'))
    assert.are.equal('application/json', wire.mime_for('/data.json'))
    assert.are.equal('application/octet-stream', wire.mime_for('/x.unknown'))
  end)
end)
