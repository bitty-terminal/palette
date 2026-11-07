-- Declarative SceneNode composition for the Bitty Palette overlay.
--
-- v1 accepts only `Text`, `Row`, `Column`, and `List` subtrees (Plugin API v1
-- Lua Surface RFC, ADR 0009). The palette composes a single `List` of `Text`
-- rows; no shader, native window, or global coordinates are used. Pure and
-- host-free so the encoding is unit testable.

local filter = require("palette.filter")

local M = {}

-- Overlay title row: keeps the surfaced scene identifiable and non-empty.
M.TITLE = "Palette"

-- Acquire-spec placeholder hint: the Core-owned input cue painted with the
-- session surface before the first content update lands.
M.PLACEHOLDER = "Filter commands"

-- Placeholder row painted when the filtered list is empty, so the overlay
-- still shows a real UI (title plus hint) instead of a bare pill.
M.EMPTY_NOTE = "No entries"

-- Placeholder row painted when the command catalog cannot be read at all, so a
-- broken source is never mistaken for an empty one.
M.UNAVAILABLE_NOTE = "Command list unavailable"

-- Placeholder row painted when a non-empty query matches nothing.
M.NO_MATCH_NOTE = "No matches"

-- Typed rows for the invocation path. `NEEDS_ARGS_NOTE` and `REFUSED_NOTE`
-- are prefixed to the command title or host error code by the caller.
M.NEEDS_ARGS_NOTE = "Needs arguments"
M.REFUSED_NOTE = "Invocation refused"
M.UNAVAILABLE_INVOKE_NOTE = "Invocation unavailable"

-- Query row: the live filter text, or the placeholder hint while empty.
function M.query_line(query)
  if type(query) ~= "string" or query == "" then
    return "> " .. M.PLACEHOLDER
  end
  return "> " .. query
end

-- Match-count row: matched commands out of the bounded scan.
function M.count_line(matched, total)
  return string.format("%d of %d commands", matched or 0, total or 0)
end

-- One command row with the selection marker. The qualified id is shown so
-- duplicate titles stay distinguishable; both fields are already bounded by
-- the caller and truncated again below.
function M.row_text(title, qualified, selected)
  local marker = selected and "> " or "  "
  local label = type(title) == "string" and title or ""
  local id = type(qualified) == "string" and qualified or ""
  if id ~= "" then
    return marker .. label .. "  " .. id
  end
  return marker .. label
end

-- Full interactive scene: title, live query, match count, an optional typed
-- note row, then the visible window rows or a placeholder. Every row is
-- truncated to the host overlay text bound. Never empty.
--
-- `state` fields: `rows` (already formatted display strings), `query`,
-- `matched`, `total`, `source_ok`, `note`, `empty_note`, and `header` (set
-- false for the legacy `default` scene without the query/count rows).
function M.view(state)
  state = state or {}
  local rows = type(state.rows) == "table" and state.rows or {}
  local children = {}
  children[1] = { kind = "Text", text = M.TITLE }
  if state.header ~= false then
    children[#children + 1] = {
      kind = "Text",
      text = filter.truncate_text(M.query_line(state.query)),
    }
    children[#children + 1] = {
      kind = "Text",
      text = filter.truncate_text(M.count_line(state.matched, state.total)),
    }
  end
  if type(state.note) == "string" and state.note ~= "" then
    children[#children + 1] = {
      kind = "Text",
      text = filter.truncate_text(state.note),
    }
  end
  if #rows == 0 then
    local empty = state.empty_note
    if type(empty) ~= "string" or empty == "" then
      empty = state.source_ok == false and M.UNAVAILABLE_NOTE or M.EMPTY_NOTE
    end
    children[#children + 1] = { kind = "Text", text = filter.truncate_text(empty) }
  else
    for _, row in ipairs(rows) do
      if type(row) == "string" then
        children[#children + 1] = { kind = "Text", text = filter.truncate_text(row) }
      end
    end
  end
  return { kind = "List", children = children }
end

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

-- Legacy default scene for an already filtered and bounded entry list: the
-- title row plus either the item rows or the placeholder row. Kept for
-- callers and tests that render a list without the interactive header; the
-- palette itself uses `view`. `source_ok` separates an empty catalog (`No
-- entries`) from a catalog the host could not serve (`Command list
-- unavailable`); nil is treated as a healthy source. Never empty.
function M.default(entries, source_ok)
  return M.view({ rows = entries, source_ok = source_ok, header = false })
end

return M
