-- Declarative SceneNode composition for the Bitty Palette overlay.
--
-- v1 accepts only `Text`, `Row`, `Column`, and `List` subtrees (Plugin API v1
-- Lua Surface RFC, ADR 0009). The palette composes a single `List` of `Text`
-- rows; no shader, native window, or global coordinates are used. Pure and
-- host-free so the encoding is unit testable.

local M = {}

-- Build the overlay list node for an already filtered and bounded entry list.
function M.list(entries)
  local children = {}
  for index, entry in ipairs(entries) do
    children[index] = { kind = "Text", text = entry }
  end
  return { kind = "List", children = children }
end

-- Empty overlay placeholder (a `List` with no rows).
function M.empty()
  return M.list({})
end

return M
