local M = {}

local active

function M.current()
  return active
end

function M.start(runtime, input)
  active = {
    runtime = runtime,
    id = runtime.id,
    display_name = runtime.display_name or runtime.id,
    color = runtime.color,
    count = 0,
    input = input or "",
    started_at = vim.loop and vim.loop.hrtime() or os.clock(),
  }
  return active
end

function M.stop(session)
  if active == session then
    active = nil
  end
end

return M
