---
name: walkthrough-propose
description: Given a (corrected) exploration walkthrough and a feature/story request, propose the target architecture -- what to add, modify, and remove -- as a reviewable "proposal" revision the engineer diffs against the exploration. Use this after walkthrough-explore has been reviewed/corrected, as the step between "understand what exists" and writing an implementation plan. Not for documenting existing code (use walkthrough-explore) or as-built code (use walkthrough-asbuilt).
---

# walkthrough-propose

The engineer has reviewed (and possibly corrected) an exploration walkthrough
of the codebase relevant to a feature. Your job now is to propose the
**target end-state**: what the architecture should look like once the
feature is built. This is not the implementation plan itself -- it's the
shared, reviewable picture that the implementation plan gets written from.

A proposal is not a new kind of artifact. It's an ordinary walkthrough
revision -- same schema, same `components`/`relationships`/`decisions`/etc
-- describing the system *as it will look after the feature exists*,
instead of as it exists today. The engineer reviews it as a **visual diff**
against the exploration revision: anything genuinely new shows up "added,"
anything you're changing shows up "changed" (with a field-by-field
before/after), anything you're removing simply isn't in your proposal and
shows up "removed." You do not compute this diff yourself -- `:WalkthroughDiff`
does, automatically, once you've written the file.

## 1. Locate walkthrough.nvim and re-read the schema

Same as the other walkthrough skills:

```
nvim --headless -c "lua print(vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/walkthrough-nvim/init.lua', false)[1], ':h:h:h'))" -c q
```

Read `<that root>/.claude/schema/walkthrough.schema.json` again, even if
recently read -- pay particular attention to the `claim_type` and `phase`
entries, which include a value specific to this skill (`PROPOSED` /
`"proposal"`) that the other three skills never use.

## 2. Read the current exploration revision

You need the `walkthrough_id` (ask if you don't know it -- it's the slug
the exploration was created under). Resolve and read the *current*
exploration revision the same way `walkthrough-reconcile` does:

```
nvim --headless -c "lua local root = require('walkthrough-nvim.persist.root').find(); local m = require('walkthrough-nvim.persist.io').read_manifest(root, '<walkthrough_id>'); print(require('walkthrough-nvim.persist.paths').revision_path(root, '<walkthrough_id>', m.current.exploration))" -c q
```

If `manifest.current.exploration` is missing, stop and tell the engineer to
run `walkthrough-explore` first -- don't propose against nothing.

## 3. Resolve the write path

```
nvim --headless -c "lua print(require('walkthrough-nvim.persist.io').next_revision_path(require('walkthrough-nvim.persist.root').find(), '<walkthrough_id>', 'proposal'))" -c q
```

This mints the next `prop-NNN` id -- a counter independent of `expl-`/`impl-`.
Resolve fresh, as always; never hand-compute it.

## 4. Write the proposal revision

Start from the exploration revision's content, then:

- **Reuse every id for anything that still exists, even if you're changing
  it.** This is the single most important rule here -- id reuse is what
  makes `:WalkthroughDiff` show a clean "changed" instead of a spurious
  remove+add. A component whose `role` or `relationships` change but is
  still conceptually the same thing keeps its id.
- **New entities** (something that doesn't exist in the codebase yet) get a
  freshly minted id (same kind-prefixed-slug convention) and
  `claim_type: "PROPOSED"`. Do **not** invent `evidence` for these -- there's
  nothing to cite, and the schema doesn't require it for `PROPOSED` claims.
  Do **not** mark them `OBSERVED`/`INFERRED`/`UNKNOWN` -- none of those mean
  "I'm proposing this."
- **Entities to remove**: simply omit them from the proposal. Don't include
  them with some "to be deleted" marker -- the diff view already renders
  "present in exploration, absent in proposal" as removed.
- **Entities you're not touching**: carry them over unchanged, same id,
  same fields, same `claim_type` (usually still `OBSERVED`) -- they give the
  engineer context for where the new pieces fit, and the diff will
  correctly show them as unchanged.
- `phase: "proposal"`, `parent_revision` set to the exploration revision id
  you read in step 2, `status: "draft"`, every entity's own `status` field
  starts `"proposed"` (that's the ordinary "not yet reviewed" default every
  skill uses -- unrelated to `claim_type: "PROPOSED"`, don't confuse them).
- Use `decisions[]` for real architectural choices about the new work (e.g.
  "should the new export logic live in the repository or service layer") --
  same shape as `walkthrough-explore` uses, `claim_type` here is usually
  `INFERRED` or `PROPOSED` depending on whether you're reasoning from
  existing patterns or proposing something with no precedent in this codebase.
- Leave `corrections: []` empty.
- `data_entities`: same reuse-vs-new-id rules as everything above -- carry
  over an existing `data:` entity unchanged if you're not touching it, reuse
  its id if you're changing its `fields`/`role`, mint a fresh `data:` id with
  `claim_type: "PROPOSED"` for a new table/document the feature needs. Only
  include this when the proposal genuinely introduces or changes persisted
  data -- most proposals won't need it. Model new ER associations
  (`has_one`/`has_many`/`belongs_to`/`many_to_many`) and new reads/writes as
  ordinary `relationships[]` entries pointing at `data:` ids, same as the
  exploration.

## 5. After writing

Stop, same as every other walkthrough skill. Tell the engineer the
proposal is ready and suggest `:WalkthroughDiff <walkthrough_id> exploration
proposal` to review it as a diff. Do not proceed to an implementation plan
in this turn -- the whole point is for the engineer to review, correct, and
confirm the *proposed* architecture first.
