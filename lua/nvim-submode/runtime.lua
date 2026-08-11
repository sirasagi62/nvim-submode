local session_api = require("nvim-submode.session")
local input = require("nvim-submode.input")

local M = {}

local function fail(message)
  error("nvim-submode.runtime: " .. message, 3)
end

local function validate(config)
  if type(config) ~= "table" then fail("config must be a table") end
  if type(config.id) ~= "string" or config.id == "" then fail("id must be a non-empty string") end
  if type(config.mappings) ~= "table" or #config.mappings == 0 then fail("mappings must be a non-empty array") end

  local mappings, seen = {}, {}
  for index, mapping in ipairs(config.mappings) do
    if type(mapping) ~= "table" or type(mapping.lhs) ~= "string" or mapping.lhs == "" then
      fail("mappings[" .. index .. "] must have a non-empty lhs")
    end
    if mapping.action ~= "exit" and type(mapping.action) ~= "function" then
      fail("mappings[" .. index .. "].action must be a function or 'exit'")
    end
    if seen[mapping.lhs] then fail("duplicate mapping lhs: " .. mapping.lhs) end
    seen[mapping.lhs] = true
    mappings[#mappings + 1] = {
      lhs = mapping.lhs, kind = mapping.kind or "key",
      action = mapping.action, desc = mapping.desc,
    }
  end

  local options = config.options or {}
  if type(options) ~= "table" then fail("options must be a table") end
  if options.timeout_ms ~= nil and (type(options.timeout_ms) ~= "number" or options.timeout_ms < 0) then
    fail("options.timeout_ms must be a non-negative number")
  end
  return {
    id = config.id, mappings = mappings,
    options = {
      timeout_ms = options.timeout_ms or 0,
      count = options.count ~= false,
      interrupt = options.interrupt or "<CR>",
    },
    on_enter = config.on_enter,
    on_leave = config.on_leave,
    display_name = config.display_name,
    color = config.color,
  }
end

function M.create(config)
  local definition = validate(config)
  local runtime = {
    id = definition.id,
    options = definition.options,
    mappings = definition.mappings,
    on_enter = definition.on_enter,
    on_leave = definition.on_leave,
    display_name = definition.display_name,
    color = definition.color,
    session = nil,
    detach = nil,
  }

  function runtime:is_active()
    return self.session ~= nil
  end

  function runtime:get_state()
    local session = self.session
    return {
      id = self.id, active = session ~= nil,
      mapping = session and session.mapping or nil,
      count = session and session.count or 0,
      input = session and session.input or "",
    }
  end

  function runtime:start(initial_input)
    if self.session then return self end
    local current = session_api.current()
    if current and current.runtime ~= self then
      current.runtime:stop("replaced")
    end
    self.session = session_api.start(self, initial_input)
    self.detach = input.attach(self, self.session)
    require("nvim-submode").notify_statusline()
    if self.on_enter then self.on_enter(self.session) end
    return self
  end

  function runtime:stop(reason)
    if not self.session then return self end
    local session = self.session
    if self.detach then self.detach(); self.detach = nil end
    self.session = nil
    session_api.stop(session)
    require("nvim-submode").notify_statusline()
    if self.on_leave then self.on_leave(session, reason or "stop") end
    return self
  end

  return runtime
end

return M
