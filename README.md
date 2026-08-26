# walkthrough.nvim

An LLM coding agent (Claude Code, first-class) externalizes its mental
model of a codebase into a structured, evidence-cited "walkthrough" —
components, relationships, data flow, decisions, and assumptions, each
tagged OBSERVED / INFERRED / UNKNOWN with source evidence. The engineer
opens it as an interactive diagram, drills into source, and can challenge
or correct any claim; corrections feed back into the next revision the
LLM writes. After implementation, a second walkthrough captures the
as-built state so the two can be diffed.

Status: early development. See the architecture/implementation plan for
the full design and phased roadmap.

## Development

```
make test   # clones plenary.nvim into .deps/ on first run, then runs the spec suite
```

Model logic (`lua/walkthrough-nvim/model/`) is pure Lua with no `vim.*`
dependency beyond `vim.json`, so it's unit-tested headless against the
fixtures in `tests/fixtures/`.
