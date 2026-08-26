---
name: walkthrough-reconcile
description: Address an engineer's corrections to a walkthrough.nvim revision by writing a new, reconciled revision. Use this after an engineer has reviewed a walkthrough in the browser UI and accepted/challenged/corrected some entities -- not for a first-pass exploration (use walkthrough-explore for that).
---

# walkthrough-reconcile

An engineer has reviewed a walkthrough you (or a previous session) wrote and
used the browser UI to accept, challenge, or correct some of its entities.
Your job is to read what they said, actually address it, and write a new
revision -- not to just acknowledge the feedback.

## 1. Locate walkthrough.nvim and re-read the schema

Same as `walkthrough-explore` step 1:

```
nvim --headless -c "lua print(vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/walkthrough-nvim/init.lua', false)[1], ':h:h:h'))" -c q
```

Read `<that root>/.claude/schema/walkthrough.schema.json` again even if you
read it recently -- don't rely on memory for field names/enums.

## 2. Read the corrected revision

You need the `walkthrough_id` (ask the user if you don't already know it --
it's the slug used when the walkthrough was first created). Resolve the
*current* exploration revision's path and read it:

```
nvim --headless -c "lua local root = require('walkthrough-nvim.persist.root').find(); local m = require('walkthrough-nvim.persist.io').read_manifest(root, '<walkthrough_id>'); print(require('walkthrough-nvim.persist.paths').revision_path(root, '<walkthrough_id>', m.current.exploration))" -c q
```

Read that file. Look at two things:

- **`corrections[]`** -- each entry has a `target` (an entity id), an
  optional `engineer_note`, and `resolved: false`. These are concrete asks.
- **Entity `status` fields** -- any entity with `status: "challenged"` or
  `status: "corrected"` needs to change in the new revision, even ones
  without a matching `corrections[]` entry (a `"challenged"` status with no
  note means "this is wrong, you figure out why" -- go re-examine the code).

## 3. Resolve the write path for the new revision

```
nvim --headless -c "lua print(require('walkthrough-nvim.persist.io').next_revision_path(require('walkthrough-nvim.persist.root').find(), '<walkthrough_id>', 'exploration'))" -c q
```

Same rule as `walkthrough-explore`: resolve fresh, never hand-compute it.

## 4. Write the reconciled revision

Start from the corrected revision's content and produce a new one:

- **Reuse every entity id that's still conceptually the same thing**, even
  if you're rewriting its `role`, `evidence`, `claim_type`, or
  `relationships`. Only mint a new id (via the same kind-prefixed-slug
  convention) for something genuinely new. Reusing ids is what lets the
  engineer's browser and the before/after diff track "the same box, updated"
  instead of showing a spurious remove+add -- there's no mechanical
  rename-detection, so this is on you to get right.
- For every correction and every challenged/corrected entity: actually
  re-investigate (re-read the cited files, search for what the engineer
  pointed at) rather than just taking their note as ground truth to copy in
  verbatim -- verify it, then update the entity's `role`/`evidence`/
  `relationships`/whatever changed.
- Reset every entity you touched back to `status: "proposed"` -- it's a new
  claim now, awaiting fresh review. Leave untouched entities' status as they
  were (an `"accepted"` entity you didn't need to change stays
  `"accepted"`).
- Set `parent_revision` to the revision id you read in step 2.
- Start this revision's `corrections` array **empty** -- the old corrections
  live in the old (immutable) revision file as a historical record; don't
  copy them forward.
- `status` (the revision-level field, not an entity's) starts at `"draft"`.

## 5. After writing

Stop, same as `walkthrough-explore`. Tell the engineer what you changed and
why, in prose, referencing the specific corrections you addressed -- this is
what lets them verify you actually understood the feedback rather than
pattern-matching it. Suggest `:WalkthroughOpen <walkthrough_id>` to review.
Do not proceed to an implementation plan in this turn.
