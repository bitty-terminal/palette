-- Declarative SceneNode composition for the Bitty Palette overlay.
--
-- v1 accepts only `Text`, `Row`, `Column`, and `List` subtrees (Plugin API v1
-- Lua Surface RFC, ADR 0009). The palette composes a single `List` of `Text`
-- rows; no shader, native window, or global coordinates are used. Pure and
-- host-free so the encoding is unit testable.

local M = {}

-- Overlay title row: keeps the surfaced scene identifiable and non-empty.
M.TITLE = "Palette"

-- Acquire-spec placeholder hint: the Core-owned input cue painted with the
-- session surface before the first content update lands.
M.PLACEHOLDER = "Filter commands"

-- Placeholder row painted when the filtered list is empty, so the overlay
-- still shows a real UI (title plus hint) instead of a bare pill.
M.EMPTY_NOTE = "No entries"

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

-- Default open scene for an already filtered and bounded entry list: the
-- title row plus either the item rows or the placeholder row. Never empty,
-- so a surfaced overlay always paints title/placeholder/items.
function M.default(entries)
  local children = {}
  children[1] = { kind = "Text", text = M.TITLE }
  if #entries == 0 then
    children[2] = { kind = "Text", text = M.EMPTY_NOTE }
  else
    for index, entry in ipairs(entries) do
      children[index + 1] = { kind = "Text", text = entry }
    end
  end
  return { kind = "List", children = children }
end

return M
