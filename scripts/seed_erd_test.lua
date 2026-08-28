-- Seeds "erd-test" with an exploration revision AND an implementation
-- revision so the new "Data Model" tab (web/renderer_erd.js) and
-- :WalkthroughDiff both have something real to render for the data-model/
-- ER feature (6e verification).
--
-- walkthrough.nvim has no real database of its own, so unlike the
-- correction-loop/propose dogfoods this is honestly a SYNTHETIC scenario --
-- the patient-cohort CSV export example from the original spec (Patient /
-- Cohort / CohortMembership), reused here for continuity rather than
-- invented fresh. File paths cited as evidence are made up to match that
-- fictional feature, not real files in this repo.
--
-- Exploration: Patient, Cohort, and a CohortMembership join table, with all
-- four ER relationship kinds (has_many, belongs_to, many_to_many) plus two
-- components that read/write the entities.
--
-- Implementation: CohortMembership is removed (folded into a simpler
-- design), Cohort gains an `archived_at` field (changed), and a new
-- ExportAuditLog entity is added -- exercising added/changed/removed/
-- unchanged for data_entities in one pass, same as diff-test does for
-- components/relationships/decisions.
--
-- Run with :source on this file.

local io_mod = require('walkthrough-nvim.persist.io')
local root = require('walkthrough-nvim.persist.root').find()
print('root:', root)

local WT = 'erd-test'

local function ev(file, line)
  return { file = file, line = line }
end

local exploration = {
  schema_version = 1,
  walkthrough_id = WT,
  revision_id = 'expl-001',
  phase = 'exploration',
  status = 'draft',
  created_by = 'claude',
  intent = { summary = 'Cohort CSV export: which patients belong to which cohorts, and who reads/writes that data.' },

  data_entities = {
    {
      id = 'data:patient',
      name = 'Patient',
      role = 'One row per patient.',
      fields = {
        { name = 'id', note = 'primary key' },
        { name = 'name' },
        { name = 'dob' },
      },
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/Patient.cs', 5) },
      status = 'proposed',
    },
    {
      id = 'data:cohort',
      name = 'Cohort',
      role = 'A named group of patients matching some criteria.',
      fields = {
        { name = 'id', note = 'primary key' },
        { name = 'name' },
        { name = 'criteria' },
      },
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/Cohort.cs', 6) },
      status = 'proposed',
    },
    {
      id = 'data:cohort_membership',
      name = 'CohortMembership',
      role = 'Join table: which patients are in which cohorts.',
      fields = {
        { name = 'id', note = 'primary key' },
        { name = 'patient_id', note = 'FK -> patient.id' },
        { name = 'cohort_id', note = 'FK -> cohort.id' },
      },
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/CohortMembership.cs', 4) },
      status = 'proposed',
    },
  },

  components = {
    {
      id = 'component:cohort-export-service',
      kind = 'component',
      name = 'CohortExportService',
      role = 'Builds the CSV export for a cohort.',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/CohortExportService.cs', 12) },
      status = 'proposed',
    },
    {
      id = 'component:cohort-enrollment-service',
      kind = 'component',
      name = 'CohortEnrollmentService',
      role = 'Adds/removes patients from a cohort.',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/CohortEnrollmentService.cs', 9) },
      status = 'proposed',
    },
  },

  relationships = {
    -- ER relationships between data entities -- all four kinds.
    {
      id = 'rel:cohort--has_many--cohort-membership',
      from = 'data:cohort',
      to = 'data:cohort_membership',
      kind = 'has_many',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/Cohort.cs', 14) },
      status = 'proposed',
    },
    {
      id = 'rel:patient--has_many--cohort-membership',
      from = 'data:patient',
      to = 'data:cohort_membership',
      kind = 'has_many',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/Patient.cs', 18) },
      status = 'proposed',
    },
    {
      id = 'rel:cohort-membership--belongs_to--patient',
      from = 'data:cohort_membership',
      to = 'data:patient',
      kind = 'belongs_to',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/CohortMembership.cs', 10) },
      status = 'proposed',
    },
    {
      id = 'rel:cohort-membership--belongs_to--cohort',
      from = 'data:cohort_membership',
      to = 'data:cohort',
      kind = 'belongs_to',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/models/CohortMembership.cs', 11) },
      status = 'proposed',
    },
    {
      id = 'rel:patient--many_to_many--cohort',
      from = 'data:patient',
      to = 'data:cohort',
      kind = 'many_to_many',
      data_shape = 'via CohortMembership',
      claim_type = 'INFERRED',
      confidence = 'medium',
      evidence = {},
      status = 'proposed',
    },
    -- Components touching entities.
    {
      id = 'rel:cohort-export-service--reads--patient',
      from = 'component:cohort-export-service',
      to = 'data:patient',
      kind = 'reads',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/CohortExportService.cs', 22) },
      status = 'proposed',
    },
    {
      id = 'rel:cohort-export-service--reads--cohort-membership',
      from = 'component:cohort-export-service',
      to = 'data:cohort_membership',
      kind = 'reads',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/CohortExportService.cs', 25) },
      status = 'proposed',
    },
    {
      id = 'rel:cohort-enrollment-service--writes--cohort-membership',
      from = 'component:cohort-enrollment-service',
      to = 'data:cohort_membership',
      kind = 'writes',
      claim_type = 'OBSERVED',
      confidence = 'high',
      evidence = { ev('src/cohort/CohortEnrollmentService.cs', 16) },
      status = 'proposed',
    },
  },
}

-- Implementation: CohortMembership removed, Cohort changed (new field),
-- ExportAuditLog added -- and every relationship that referenced the
-- removed entity is dropped too, so this revision stays schema-valid on
-- its own (no dangling `data:cohort_membership` references).
local implementation = vim.deepcopy(exploration)
implementation.revision_id = 'impl-001'
implementation.phase = 'implementation'
implementation.parent_revision = 'expl-001'
implementation.intent = { summary = 'As built: CohortMembership folded away, export runs write an audit log.' }

local function remove(list, id)
  for i = #list, 1, -1 do
    if list[i].id == id then
      table.remove(list, i)
    end
  end
end

remove(implementation.data_entities, 'data:cohort_membership')
remove(implementation.relationships, 'rel:cohort--has_many--cohort-membership')
remove(implementation.relationships, 'rel:patient--has_many--cohort-membership')
remove(implementation.relationships, 'rel:cohort-membership--belongs_to--patient')
remove(implementation.relationships, 'rel:cohort-membership--belongs_to--cohort')
remove(implementation.relationships, 'rel:cohort-export-service--reads--cohort-membership')
remove(implementation.relationships, 'rel:cohort-enrollment-service--writes--cohort-membership')

for _, e in ipairs(implementation.data_entities) do
  if e.id == 'data:cohort' then
    table.insert(e.fields, { name = 'archived_at', note = 'nullable, set when a cohort is retired' })
    e.evidence = { ev('src/cohort/models/Cohort.cs', 20) }
  end
end

table.insert(implementation.data_entities, {
  id = 'data:export_audit_log',
  name = 'ExportAuditLog',
  role = 'One row per completed cohort CSV export, for compliance.',
  fields = {
    { name = 'id', note = 'primary key' },
    { name = 'cohort_id', note = 'FK -> cohort.id' },
    { name = 'exported_at' },
  },
  claim_type = 'OBSERVED',
  confidence = 'high',
  evidence = { ev('src/cohort/models/ExportAuditLog.cs', 5) },
  status = 'proposed',
})

table.insert(implementation.relationships, {
  id = 'rel:cohort-export-service--writes--export-audit-log',
  from = 'component:cohort-export-service',
  to = 'data:export_audit_log',
  kind = 'writes',
  claim_type = 'OBSERVED',
  confidence = 'high',
  evidence = { ev('src/cohort/CohortExportService.cs', 31) },
  status = 'proposed',
})

local function save(model)
  local ok, err = io_mod.write_revision(root, model)
  print(model.revision_id, 'ok=', ok, 'err=', err)
end

save(exploration)
save(implementation)
