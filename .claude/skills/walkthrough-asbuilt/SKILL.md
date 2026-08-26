---
name: walkthrough-asbuilt
description: Write a walkthrough.nvim revision describing the as-built state after implementing a feature, so the engineer can see a visual before/after diff against the original exploration walkthrough. Use this right after finishing an implementation that started from a walkthrough-explore/-reconcile walkthrough -- not for a first-pass exploration.
---

# walkthrough-asbuilt

You just finished implementing a feature that started from a walkthrough. Write
an **implementation** revision describing what you actually built, so
`:WalkthroughDiff` can show the engineer a visual before/after: what changed,
what's new, what got removed, and where the implementation deviated from the
original model.

This is not a git-diff summary. It's the same kind of curated,
evidence-cited model as an exploration revision -- just describing the
code as it exists now instead of as you found it.

## 1. Locate walkthrough.nvim and re-read the schema

Same as the other walkthrough skills:

```
nvim --headless -c "lua print(vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/walkthrough-nvim/init.lua', false)[1], ':h:h:h'))" -c q
```

Read `<that root>/.claude/schema/walkthrough.schema.json`.

## 2. Resolve the write path

You need the `walkthrough_id` used for this feature's exploration walkthrough
(ask if you don't know it). This revision's `phase` is `"implementation"`,
not `"exploration"` -- pass that explicitly:

```
nvim --headless -c "lua print(require('walkthrough-nvim.persist.io').next_revision_path(require('walkthrough-nvim.persist.root').find(), '<walkthrough_id>', 'implementation'))" -c q
```

This mints an `impl-NNN` id, independent of the `expl-NNN` counter for the
same walkthrough. Resolve fresh, as always -- never hand-compute it.

## 3. Read the final exploration revision for id continuity

Read the walkthrough's current exploration revision (the same
`next_revision_path`-style resolution, with `'exploration'` instead of
`'implementation'`, gives you its manifest; `manifest.current.exploration`
names it) -- **not** to copy from, but so you know which entity ids to
reuse for anything that survived unchanged or moved with modest changes.
The diff view compares entities by id; reusing ids for the same
conceptual component/relationship/decision is what makes "unchanged" and
"changed" show up correctly instead of everything looking like a
remove+add.

## 4. Write the implementation revision

Describe the system **as it now exists**, at the same curated scope as the
original exploration (the feature's slice, not the whole codebase):

- `phase: "implementation"`, `parent_revision` set to the exploration
  revision you read in step 3, `status: "draft"`.
- Every claim should now be `claim_type: "OBSERVED"` with real evidence --
  you just wrote this code, there's no excuse for `INFERRED`/`UNKNOWN` here
  unless something is genuinely still undecided (e.g. a follow-up TODO).
- Reuse ids for components/relationships/decisions that are conceptually
  the same as in the exploration revision, even if their `role`,
  `evidence`, or connections changed. Mint new ids (same kind-prefixed-slug
  convention) only for things that are genuinely new.
- For anything the exploration model got wrong or that changed during
  implementation, don't just silently fix it -- note it. A `decisions[]`
  entry is the right place for "we planned X, built Y instead, because
  Z" -- this is exactly the kind of deviation the before/after diff exists
  to surface.
- Leave `corrections: []` empty; this is a fresh revision, not a
  correction of the implementation one.

## 5. After writing

Tell the engineer the implementation revision is ready and suggest
`:WalkthroughDiff <walkthrough_id>` to see the before/after. Stop there --
this skill's job ends at writing the artifact, not narrating the diff for
them in prose.
