-- walkthrough-nvim.model.evidence — evidence-citation shape and the
-- OBSERVED/INFERRED/UNKNOWN confidence contract. Pure Lua.
--
-- The core rule this module encodes: an OBSERVED claim must never be
-- presentable as objectively verified fact without a citation the
-- engineer can jump to and check. INFERRED/UNKNOWN claims may cite
-- evidence too (e.g. "inferred from patterns in these three files") but
-- are not required to.

local M = {}

local CLAIM_TYPE = require('walkthrough-nvim.model.schema').CLAIM_TYPE

local function is_nonempty_string(v)
  return type(v) == 'string' and v ~= ''
end

--- Validate a single evidence entry: { file, line?, symbol? }.
-- @return ok boolean
-- @return err string|nil
function M.validate_entry(e)
  if type(e) ~= 'table' then
    return false, 'evidence entry must be an object'
  end
  if not is_nonempty_string(e.file) then
    return false, 'file: required non-empty string'
  end
  if e.line ~= nil and (type(e.line) ~= 'number' or e.line < 1) then
    return false, 'line: must be a positive number when present'
  end
  if e.symbol ~= nil and not is_nonempty_string(e.symbol) then
    return false, 'symbol: must be a non-empty string when present'
  end
  return true, nil
end

--- Validate an evidence array, returning path-prefixed error strings.
function M.validate_list(evidence, path)
  local errors = {}
  if evidence == nil then
    return errors
  end
  if type(evidence) ~= 'table' then
    errors[#errors + 1] = path .. ': evidence must be an array'
    return errors
  end
  for i, e in ipairs(evidence) do
    local ok, err = M.validate_entry(e)
    if not ok then
      errors[#errors + 1] = string.format('%s[%d].%s', path, i, err)
    end
  end
  return errors
end

--- Whether a claim of this type is required to cite evidence.
function M.requires_evidence(claim_type)
  return claim_type == CLAIM_TYPE.OBSERVED
end

--- Full check for a claim-bearing entity's evidence: shape validity plus
--- the OBSERVED-requires-evidence rule.
function M.check_claim_evidence(claim_type, evidence, path)
  local errors = M.validate_list(evidence, path .. '.evidence')
  if M.requires_evidence(claim_type) and (type(evidence) ~= 'table' or #evidence == 0) then
    errors[#errors + 1] = path .. ': OBSERVED claims require at least one evidence entry'
  end
  return errors
end

return M
