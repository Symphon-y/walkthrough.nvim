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

## Setup

Add the plugin to your Neovim config as you would any other (a plain
`'Symphon-y/walkthrough.nvim'` lazy.nvim/packer spec works on a fresh
machine — no local checkout required, lazy.nvim clones it directly).

Claude Code's skills (`walkthrough-explore`/`-reconcile`/`-propose`/
`-asbuilt`) live in this repo but need to be installed into Claude Code's
**global** skill directory (`~/.claude/skills/`) to be available in
whatever project you're actually walking through — not just this one. Run
once, in Neovim, after installing or updating the plugin:

```
:WalkthroughSetup
```

This creates a directory junction/symlink per skill (falling back to a
plain copy if linking isn't possible on your machine) so future `git pull`s
of this plugin keep the installed skills in sync automatically — no need to
re-run it after every update. It also runs itself silently the first time
you use any `:Walkthrough*` command in a session, so in practice you may
never need to run it by hand after the first time.

If `~/.claude/skills/<name>` already exists and isn't a link this plugin
created (e.g. an unrelated skill with the same name), `:WalkthroughSetup`
warns and leaves it alone — use `:WalkthroughSetup!` to overwrite it.
`:checkhealth walkthrough-nvim` reports each skill's current install state.

## Development

```
make test   # clones plenary.nvim into .deps/ on first run, then runs the spec suite
```

Model logic (`lua/walkthrough-nvim/model/`) is pure Lua with no `vim.*`
dependency beyond `vim.json`, so it's unit-tested headless against the
fixtures in `tests/fixtures/`.
