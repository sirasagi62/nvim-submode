local vim = vim
local submode = require("nvim-submode")

local M = {}

local function fail(message)
  error("nvim-submode.runtime: " .. message, 3)
end

local function copy_state(state)
  local copy = {}
  for key, value in pairs(state) do
    copy[key] = value
  end
  return copy
end

local function validate_options(options)
  options = options or {}
  if type(options) ~= "table" then
    fail("options must be a table")
  end

  for field in pairs(options) do
    if field ~= "timeout_ms" and field ~= "count" and field ~= "interrupt" then
      fail("unknown option: " .. tostring(field))
    end
  end

  if options.timeout_ms ~= nil
      and (type(options.timeout_ms) ~= "number" or options.timeout_ms < 0) then
    fail("options.timeout_ms must be a non-negative number")
  end
  if options.count ~= nil and type(options.count) ~= "boolean" then
    fail("options.count must be a boolean")
  end
  if options.interrupt ~= nil
      and (type(options.interrupt) ~= "string" or options.interrupt == "") then
    fail("options.interrupt must be a non-empty string")
  end

  return {
    timeout_ms = options.timeout_ms or 0,
    count = options.count ~= false,
    interrupt = options.interrupt or "<CR>",
  }
end

local function validate_mappings(mappings)
  if type(mappings) ~= "table" or #mappings == 0 then
    fail("mappings must be a non-empty array")
  end

  local normalized = {}
  local seen = {}
  for index, mapping in ipairs(mappings) do
    if type(mapping) ~= "table" then
      fail("mappings[" .. index .. "] must be a table")
    end
    for field in pairs(mapping) do
      if field ~= "lhs" and field ~= "desc" and field ~= "action" and field ~= "kind" then
        fail("mappings[" .. index .. "] has unknown field: " .. tostring(field))
      end
    end
    if type(mapping.lhs) ~= "string" or mapping.lhs == "" then
      fail("mappings[" .. index .. "].lhs must be a non-empty string")
    end
    if mapping.action ~= "exit" and type(mapping.action) ~= "function" then
      fail("mappings[" .. index .. "].action must be a function or 'exit'")
    end

    local kind = mapping.kind or "mapping"
    if kind ~= "mapping" and kind ~= "any" then
      fail("mappings[" .. index .. "].kind must be 'mapping' or 'any'")
    end
    local has_any = mapping.lhs:find("<any>", 1, true) ~= nil
    if has_any and kind ~= "any" then
      fail("mappings[" .. index .. "].kind must be 'any' when lhs contains <any>")
    end
    if kind == "any" and not has_any then
      fail("mappings[" .. index .. "].lhs must contain <any> for kind 'any'")
    end
    if seen[mapping.lhs] then
      fail("duplicate mapping lhs: " .. mapping.lhs)
    end
    seen[mapping.lhs] = true

    normalized[#normalized + 1] = {
      lhs = mapping.lhs,
      desc = mapping.desc,
      action = mapping.action,
      kind = kind,
    }
  end
  return normalized
end

local function validate_spec(spec)
  if type(spec) ~= "table" then
    fail("spec must be a table")
  end
  for field in pairs(spec) do
    if field ~= "id" and field ~= "mappings" and field ~= "options"
        and field ~= "on_enter" and field ~= "on_leave" then
      fail("unknown field: " .. tostring(field))
    end
  end
  if type(spec.id) ~= "string" or spec.id == "" then
    fail("id must be a non-empty string")
  end
  if spec.on_enter ~= nil and type(spec.on_enter) ~= "function" then
    fail("on_enter must be a function")
  end
  if spec.on_leave ~= nil and type(spec.on_leave) ~= "function" then
    fail("on_leave must be a function")
  end

  return {
    id = spec.id,
    mappings = validate_mappings(spec.mappings),
    options = validate_options(spec.options),
    on_enter = spec.on_enter,
    on_leave = spec.on_leave,
  }
end

local function normalize_action_result(result)
  if result == nil then
    return "", nil
  end
  if type(result) ~= "table" then
    fail("action result must be nil or a table")
  end
  if result.input ~= nil and type(result.input) ~= "string" then
    fail("action result.input must be a string")
  end
  if result.exit ~= nil and type(result.exit) ~= "boolean" then
    fail("action result.exit must be a boolean")
  end
  return result.input or "", result.exit and submode.EXIT_SUBMODE or nil
end

function M.create(spec)
  local definition = validate_spec(spec)
  local runtime = {
    id = definition.id,
    active = false,
    mapping = nil,
    count = 1,
    leave_reason = nil,
  }

  function runtime:get_state()
    return copy_state({
      id = self.id,
      active = self.active,
      mapping = self.mapping,
      count = self.count,
    })
  end

  function runtime:is_active()
    return self.active
  end

  local function update_state(active, mapping, count)
    runtime.active = active
    runtime.mapping = mapping
    runtime.count = count or 1
  end

  local function leave()
    if not runtime.active then
      return
    end
    update_state(false, nil, 1)
    local reason = runtime.leave_reason or "escape"
    runtime.leave_reason = nil
    if definition.on_leave then
      definition.on_leave(reason, runtime:get_state())
    end
  end

  function runtime:start()
    if self.active then
      return self
    end

    self.active = true

    local keymaps = {}
    for _, mapping in ipairs(definition.mappings) do
      keymaps[#keymaps + 1] = {
        mapping.lhs,
        function(count, lhs, captures)
          local context = {
            runtime = self,
            id = self.id,
            lhs = mapping.lhs,
            count = count > 0 and count or 1,
            captures = captures or {},
            input = nil,
          }
          update_state(true, mapping.lhs, context.count)
          local result
          if mapping.action == "exit" then
            result = { exit = true }
          else
            result = mapping.action(context)
          end
          local input, exit = normalize_action_result(result)
          return input, exit
        end,
      }
    end

    local mode = submode.build_submode({
      name = definition.id,
      display_name = definition.id,
      timeoutlen = definition.options.timeout_ms,
      is_count_enable = definition.options.count,
      after_enter = function()
        update_state(true, nil, 1)
        if definition.on_enter then
          definition.on_enter(self:get_state())
        end
      end,
      after_leave = leave,
    }, keymaps)

    local ok, err = pcall(submode.enable, mode)
    if not ok then
      update_state(false, nil, 1)
      error(err, 0)
    end
    return self
  end

  function runtime:stop()
    if not self.active then
      return self
    end
    self.leave_reason = "stop"
    submode.disable()
    leave()
    return self
  end

  return runtime
end

return M
