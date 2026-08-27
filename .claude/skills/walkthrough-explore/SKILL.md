---
name: walkthrough-explore
description: Externalize your mental model of a codebase into a walkthrough.nvim artifact before writing an implementation plan. Use this whenever a story/feature request asks you to explore a codebase and the user wants to review your understanding visually before planning -- not for small, obvious changes.
---

# walkthrough-explore

You are about to explore a codebase for a feature/story. Instead of jumping
straight to an implementation plan, externalize what you find as a
**walkthrough**: a structured, evidence-cited model of the relevant slice of
the system that the engineer can open in a browser (via `:WalkthroughOpen` in
Neovim), explore visually, and correct before you plan the implementation.

This is not a code map. Curate ruthlessly: include only what the engineer
needs to participate meaningfully in the implementation discussion, not
everything you found. Think "senior engineer briefing a colleague at a
whiteboard," not "here's every symbol I touched."

## 1. Locate walkthrough.nvim and the schema

Run this from the project you are exploring (it must be inside a Neovim
runtimepath that has walkthrough.nvim installed -- it will, if the user set
it up per the plugin's README):

```
nvim --headless -c "lua print(vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/walkthrough-nvim/init.lua', false)[1], ':h:h:h'))" -c q
```

This prints walkthrough.nvim's installation root. Read
`<that root>/.claude/schema/walkthrough.schema.json` -- it is the full,
authoritative field-by-field contract for a revision (required fields, id
patterns, enums). Follow it exactly. If this command errors or prints
nothing, stop and tell the user walkthrough.nvim isn't set up in this
Neovim config yet, rather than guessing at the shape.

## 2. Pick a walkthrough_id

A short kebab-case slug for the feature/story, e.g. `checkout-refund-flow`.
Reuse the same slug for `walkthrough-reconcile` and `walkthrough-asbuilt`
runs on the same feature later -- it's how they find each other.

## 3. Resolve the exact file to write

Run (same repo, same Neovim config):

```
nvim --headless -c "lua print(require('walkthrough-nvim.persist.io').next_revision_path(require('walkthrough-nvim.persist.root').find(), '<walkthrough_id>', 'exploration'))" -c q
```

This mints the next `expl-NNN` revision id and returns the exact path to
write to (creating the `revisions/` directory if needed). Always resolve
this fresh, right before writing -- never guess or reuse a path from a
previous run, and never hand-compute the repo-hash directory yourself: that
hashing logic lives in one place (`persist/paths.lua`) specifically so it
never drifts between this skill and the plugin.

## 4. Explore, then write the revision

Explore the codebase with your normal tools. For each component,
relationship, decision, and assumption you include:

- Tag it `claim_type: "OBSERVED"` only if you read the actual code that
  supports it, and cite the file/line in `evidence`. The validator rejects
  an OBSERVED claim with no evidence -- this is not optional.
- Tag it `"INFERRED"` when you're pattern-matching or reasoning from
  convention, not certain. Evidence is encouraged but not required; say so
  in `role`/`reason` text (e.g. "inferred from patterns in similar
  services").
- Tag it `"UNKNOWN"` when you genuinely don't know and are flagging a gap
  for the engineer, not asserting anything.
- Set every entity's `status` to `"proposed"` (the engineer's corrections
  are what advance it) -- except assumptions, which default to
  `"unresolved"`.
- Do not write a `corrections` array -- leave it absent or empty. That's the
  engineer's channel back to you, not yours to fill.

Include:

- `intent`: what feature/story this is, in one or two sentences.
- `components`: only the ones that actually participate in this feature.
- `relationships`: how they connect, each labeled with the data shape
  crossing it (`data_shape`).
- `decisions`: only where there's a real fork you're aware of (an existing
  pattern that could have gone another way, or a choice the implementation
  will have to make) -- not every file is a decision.
- `assumptions`: things you couldn't verify and are assuming.
- `data_lineage` / `flows`: include when the feature is fundamentally about
  a request flow or a piece of data changing shape end-to-end -- skip them
  when they wouldn't add anything beyond what `relationships` already shows.
- `data_entities`: include only when the feature is genuinely about data the
  codebase persists (DB tables, documents, etc.) -- give each entity a
  `data:`-prefixed id and a few notable `fields`. Model ER associations
  between two data entities (`has_one`/`has_many`/`belongs_to`/`many_to_many`)
  and "this component reads/writes that entity" (`reads`/`writes`) as
  ordinary `relationships[]` entries pointing at `data:` ids -- there is no
  separate ER relationship array. Skip `data_entities` entirely for
  features that don't touch persisted data.

Write the JSON to the path from step 3 using your file-editing tool
directly. Do not run `:WalkthroughOpen` yourself or ask the user to -- tell
them the walkthrough is ready and to open it themselves when ready to
review; you may suggest the command (`:WalkthroughOpen <walkthrough_id>`).

## 5. After writing

Stop. Do not proceed to an implementation plan in the same turn. The whole
point of this artifact is for the engineer to review, correct, and confirm
the model *before* planning starts. Tell them what you wrote and where, and
wait.
