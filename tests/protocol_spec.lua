local protocol = require('walkthrough-nvim.server.protocol')

local function spy_engine()
  local calls = {}
  local function record(name)
    return function(...)
      calls[#calls + 1] = { name = name, args = { ... } }
    end
  end
  return {
    calls = calls,
    focus = record('focus'),
    clear_focus = record('clear_focus'),
    reveal = record('reveal'),
    reveal_at = record('reveal_at'),
    accept = record('accept'),
    challenge = record('challenge'),
    correct = record('correct'),
  }
end

describe('walkthrough-nvim.server.protocol', function()
  it('routes focus and reveal by nodeId', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'focus', nodeId = 'component:x' }, eng)
    protocol.dispatch({ action = 'reveal', nodeId = 'component:x' }, eng)
    assert.are.equal('focus', eng.calls[1].name)
    assert.are.equal('component:x', eng.calls[1].args[1])
    assert.are.equal('reveal', eng.calls[2].name)
  end)

  it('routes clearFocus with no params', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'clearFocus' }, eng)
    assert.are.equal('clear_focus', eng.calls[1].name)
    assert.are.equal(0, #eng.calls[1].args)
  end)

  it('routes revealAt by file+line', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'revealAt', file = 'src/x.cs', line = 42 }, eng)
    assert.are.equal('reveal_at', eng.calls[1].name)
    assert.are.same({ 'src/x.cs', 42 }, eng.calls[1].args)
  end)

  it('routes accept/challenge by nodeId and correct by nodeId+note', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'accept', nodeId = 'component:x' }, eng)
    protocol.dispatch({ action = 'challenge', nodeId = 'component:x' }, eng)
    protocol.dispatch({ action = 'correct', nodeId = 'component:x', note = 'wrong' }, eng)
    assert.are.equal('accept', eng.calls[1].name)
    assert.are.equal('challenge', eng.calls[2].name)
    assert.are.equal('correct', eng.calls[3].name)
    assert.are.same({ 'component:x', 'wrong' }, eng.calls[3].args)
  end)

  it('errors on an unknown action without touching the engine', function()
    local eng = spy_engine()
    local res = protocol.dispatch({ action = 'launchMissiles' }, eng)
    assert.are.equal('error', res.status)
    assert.is_truthy(res.message:find('unknown'))
    assert.are.equal(0, #eng.calls)
  end)

  it('errors when a required parameter is missing', function()
    local eng = spy_engine()
    local res = protocol.dispatch({ action = 'focus' }, eng)
    assert.are.equal('error', res.status)
    assert.are.equal(0, #eng.calls)
  end)

  it('decodes a raw JSON string and routes it', function()
    local eng = spy_engine()
    local res = protocol.handle('{"action":"reveal","nodeId":"component:x"}', eng)
    assert.are.equal('ok', res.status)
    assert.are.equal('reveal', eng.calls[1].name)
  end)

  it('errors on malformed JSON', function()
    local eng = spy_engine()
    local res = protocol.handle('{not json', eng)
    assert.are.equal('error', res.status)
    assert.are.equal(0, #eng.calls)
  end)
end)
