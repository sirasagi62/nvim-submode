local matcher = require("nvim-submode.matcher")

local M = {}

function M.attach(runtime, session)
  local ns = vim.api.nvim_create_namespace("nvim-submode.runtime." .. runtime.id)
  local timer

  local function detach()
    if timer then timer:stop(); timer:close(); timer = nil end
    vim.on_key(nil, ns)
  end

  local function stop(reason)
    detach()
    runtime:stop(reason)
  end

  local function execute(mapping)
    local context = {
      runtime = runtime, session = session, id = runtime.id,
      lhs = mapping.lhs, input = session.input,
      count = session.count > 0 and session.count or 1,
    }
    local action = mapping.action == "exit" and { exit = true } or mapping.action(context)
    action = action or {}
    session.input, session.count = "", 0
    vim.schedule(function()
      if action.input then
        local keys = vim.api.nvim_replace_termcodes(action.input, true, false, true)
        vim.api.nvim_feedkeys(keys, "m", false)
      end
      require("nvim-submode").notify_statusline()
      if action.exit then stop("action") end
    end)
  end

  local function callback(_, typed)
    local key = vim.fn.keytrans(typed ~= "" and typed or "")
    if key == "" then return "" end
    if key == runtime.options.interrupt or key == "<Esc>" then
      vim.schedule(function() stop("interrupt") end)
      return ""
    end

    if runtime.options.count and session.input == "" and key:match("^%d$") then
      session.count = session.count * 10 + tonumber(key)
      return ""
    end

    session.input = session.input .. key
    local result = matcher.match({ mappings = runtime.mappings, input = session.input })
    if result.kind == "none" then
      session.input = ""
      session.count = 0
      return ""
    end
    if result.kind == "prefix" then
      if timer then timer:stop(); timer:close() end
      if runtime.options.timeout_ms and runtime.options.timeout_ms > 0 then
        timer = vim.defer_fn(function()
          timer = nil
          if result.mapping then execute(result.mapping) else stop("timeout") end
        end, runtime.options.timeout_ms)
      end
      return ""
    end

    execute(result.mapping)
    return ""
  end

  vim.on_key(callback, ns)
  return detach
end

return M
