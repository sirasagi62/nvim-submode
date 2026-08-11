local M = { callbacks = {} }

function M.notify()
  for _, callback in ipairs(M.callbacks) do
    vim.schedule(callback)
  end
end

return M
