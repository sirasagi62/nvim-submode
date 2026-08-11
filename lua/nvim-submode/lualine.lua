local M = {}
local has_lualine, lualine = pcall(require, "lualine")
local submode = require("nvim-submode")
local get_mode = has_lualine and lualine.get_mode or function()
  return vim.fn.mode()
end
local unregister

function M.setup()
  if has_lualine and not unregister then
    unregister = submode.register_statusline(function()
      lualine.refresh()
    end)
  end
  return M
end

function M.teardown()
  if unregister then
    unregister()
    unregister = nil
  end
end

if has_lualine then
  M.setup()

  function M.submodeNameLualine()
    return submode.get_statusline().display_name or get_mode()
  end

  function M.submodeNameLualineWithBaseMode()
    local state = submode.get_statusline()
    if state.display_name then
      return state.display_name .. "(" .. get_mode() .. ")"
    end
    return get_mode()
  end

  function M.submodeLualineColor()
    local color = submode.get_statusline().color
    return color and { bg = color } or nil
  end
end

return M
