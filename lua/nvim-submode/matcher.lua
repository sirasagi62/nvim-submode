local M = {}

local function pattern_parts(lhs)
  local parts, position = {}, 1
  while true do
    local start, finish = lhs:find("<any>", position, true)
    if not start then
      if position <= #lhs then parts[#parts + 1] = lhs:sub(position) end
      break
    end
    if start > position then parts[#parts + 1] = lhs:sub(position, start - 1) end
    parts[#parts + 1] = false
    position = finish + 1
  end
  return parts
end

local function matches(lhs, input)
  local parts = pattern_parts(lhs)
  local rest, exact = input, true
  for _, part in ipairs(parts) do
    if part == false then
      if #rest == 0 then return false, false end
      rest = rest:sub(2)
    else
      if rest:sub(1, #part) ~= part then return false, false end
      rest = rest:sub(#part + 1)
    end
  end
  return #rest == 0, #rest == 0 and exact or false
end

function M.match(args)
  local input = args.input or ""
  local candidates = {}
  local exact

  for _, mapping in ipairs(args.mappings or {}) do
    local lhs = mapping.lhs
    local exact_match = matches(lhs, input)
    if exact_match then
      exact = mapping
    elseif lhs:sub(1, #input) == input then
      candidates[#candidates + 1] = mapping
    elseif lhs:find("<any>", 1, true) then
      local prefix = lhs:sub(1, lhs:find("<any>", 1, true) - 1)
      if input:sub(1, #prefix) == prefix and #input <= #prefix + #lhs - #prefix - 5 then
        candidates[#candidates + 1] = mapping
      end
    end
  end

  if exact and #candidates > 0 then
    return { kind = "prefix", mapping = exact, candidates = candidates }
  end
  if exact then
    return { kind = "exact", mapping = exact, candidates = candidates }
  end
  if #candidates > 0 then
    return { kind = "prefix", candidates = candidates }
  end
  return { kind = "none", candidates = {} }
end

return M
