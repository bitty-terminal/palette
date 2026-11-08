-- Bounded filtering and truncation policy for Bitty Palette
-- (bitty-terminal.palette).
--
-- Pure functions with no host dependency, so the palette policy is unit
-- testable in plain Lua. This module is the authoritative realization of
-- the palette envelope: at most `128` matched entries, a `12`-row visible
-- window, a `128`-character query, and `128`-character display text per entry
-- (the host overlay text bound `MAX_OVERLAY_TEXT_LEN`). The match bound and
-- display text values were carried over from the historical bundled Rust
-- realization, which was removed from `bitty` by PR #1611 (commit
-- `67cdcc14`); no Rust counterpart remains. The input bound `MAX_INPUT` is a
-- palette-local policy: the host command catalog is untrusted data, so a
-- single filter pass examines at most `MAX_INPUT` candidates regardless of
-- how large the table is (the historical bundled realization trusted its
-- input).

local M = {}

M.MAX_ENTRIES = 128
M.MAX_QUERY_CHARS = 128
M.MAX_TEXT_CHARS = 128

-- Maximum command rows painted in one overlay frame. The match count reflects
-- the bounded match list; only the visible window is capped, so a long
-- catalog never produces an unbounded scene.
M.MAX_VISIBLE = 12

-- Maximum candidate entries examined per filter pass. Oversized candidate
-- tables are cut at this bound and the cut is reported through the filter
-- stats (`truncated`), so callers never silently lose input either.
M.MAX_INPUT = 1024

-- Count Unicode code points. The restricted plugin VM retains `utf8`; the
-- byte scan is a fallback that never splits a code point.
local function char_count(text)
  if utf8 ~= nil and utf8.len ~= nil then
    local count = utf8.len(text)
    if type(count) == "number" then
      return count
    end
  end
  local count = 0
  local index = 1
  local length = #text
  while index <= length do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
    end
    index = index + 1
  end
  return count
end

-- Truncate `text` to `max` code points without splitting a UTF-8 sequence.
local function char_slice(text, max)
  if max <= 0 then
    return ""
  end
  if char_count(text) <= max then
    return text
  end
  if utf8 ~= nil and utf8.offset ~= nil then
    local offset = utf8.offset(text, max + 1)
    if offset ~= nil then
      return string.sub(text, 1, offset - 1)
    end
  end
  local count = 0
  local index = 1
  local length = #text
  while index <= length do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
      if count > max then
        return string.sub(text, 1, index - 1)
      end
    end
    index = index + 1
  end
  return text
end

M.char_count = char_count

-- Truncate one display string to the overlay text bound.
function M.truncate_text(text)
  return char_slice(text, M.MAX_TEXT_CHARS)
end

-- Truncate one query string to the query bound.
function M.truncate_query(text)
  return char_slice(text, M.MAX_QUERY_CHARS)
end

-- Remove the last Unicode code point from `text` (Backspace semantics). The
-- byte scan fallback never splits a UTF-8 sequence.
function M.drop_last_char(text)
  if type(text) ~= "string" or text == "" then
    return ""
  end
  local count = char_count(text)
  if count <= 1 then
    return ""
  end
  if utf8 ~= nil and utf8.offset ~= nil then
    local offset = utf8.offset(text, count)
    if offset ~= nil then
      return string.sub(text, 1, offset - 1)
    end
  end
  local index = #text
  while index > 1 do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      return string.sub(text, 1, index - 1)
    end
    index = index - 1
  end
  return ""
end

-- Normalize one `bitty.commands.list` row into the palette's display shape.
-- The host serves `{ plugin, id, qualified, title }`; string rows and rows
-- with a missing title are tolerated so a malformed catalog entry is skipped
-- instead of reaching the overlay. Returns nil for an unusable row.
function M.normalize_row(row)
  if type(row) == "string" then
    if row == "" then
      return nil
    end
    local text = char_slice(row, M.MAX_TEXT_CHARS)
    return { id = text, title = text, plugin = "", qualified = text }
  end
  if type(row) ~= "table" then
    return nil
  end
  local id = type(row.id) == "string" and char_slice(row.id, M.MAX_TEXT_CHARS) or ""
  local title = type(row.title) == "string" and char_slice(row.title, M.MAX_TEXT_CHARS) or ""
  local plugin = type(row.plugin) == "string" and char_slice(row.plugin, M.MAX_TEXT_CHARS) or ""
  local qualified = ""
  if type(row.qualified) == "string" then
    qualified = char_slice(row.qualified, M.MAX_TEXT_CHARS)
  end
  if qualified == "" and plugin ~= "" and id ~= "" then
    qualified = char_slice(plugin .. ":" .. id, M.MAX_TEXT_CHARS)
  end
  if title == "" then
    title = qualified ~= "" and qualified or id
  end
  if title == "" then
    return nil
  end
  return { id = id, title = title, plugin = plugin, qualified = qualified }
end

-- Case-insensitive substring match over the row id, title, owning plugin id,
-- and qualified command id. The query is already lowercased and truncated by
-- the caller.
local function row_matches(entry, needle)
  local fields = { entry.id, entry.title, entry.plugin, entry.qualified }
  for _, field in ipairs(fields) do
    if type(field) == "string" then
      -- Bound the per-field match work to the same overlay text ceiling the
      -- display uses, so a hostile catalog row cannot make one scan pass
      -- unbounded.
      local haystack = string.lower(char_slice(field, M.MAX_TEXT_CHARS))
      if string.find(haystack, needle, 1, true) ~= nil then
        return true
      end
    end
  end
  return false
end

-- Filter and normalize the host command catalog. Returns the bounded matched
-- rows plus stats: `scanned` is the number of candidates examined, `matched`
-- is the number of matches inside the `MAX_ENTRIES` output bound (so the
-- count never names a row the caller cannot select), and `truncated` reports
-- the `MAX_INPUT` cut. Non-table input fails closed to an empty list.
function M.filter_commands(rows, query)
  if type(rows) ~= "table" then
    return {}, { scanned = 0, matched = 0, truncated = false }
  end
  local needle = string.lower(char_slice(query or "", M.MAX_QUERY_CHARS))
  local out = {}
  local scanned = 0
  local truncated = false
  for _, row in ipairs(rows) do
    if scanned >= M.MAX_INPUT then
      truncated = true
      break
    end
    scanned = scanned + 1
    if #out < M.MAX_ENTRIES then
      local entry = M.normalize_row(row)
      if entry ~= nil and (needle == "" or row_matches(entry, needle)) then
        out[#out + 1] = entry
      end
    end
  end
  return out, { scanned = scanned, matched = #out, truncated = truncated }
end

-- Case-insensitive substring filter, bounded to `MAX_ENTRIES` output rows and
-- `MAX_INPUT` examined candidates. The query is truncated to
-- `MAX_QUERY_CHARS`; non-string entries are skipped; matching entry text is
-- truncated to the overlay text bound. An empty query returns the first
-- `MAX_ENTRIES` entries unchanged in order.
--
-- Non-table input fails closed to an empty list. Returns the bounded output
-- list plus a stats table: `scanned` is the number of candidates examined and
-- `truncated` is true when the scan stopped at `MAX_INPUT` while further
-- candidates existed.
function M.filter(entries, query)
  if type(entries) ~= "table" then
    return {}, { scanned = 0, truncated = false }
  end
  local bounded_query = char_slice(query or "", M.MAX_QUERY_CHARS)
  local needle = string.lower(bounded_query)
  local out = {}
  local scanned = 0
  local truncated = false
  for _, entry in ipairs(entries) do
    if #out >= M.MAX_ENTRIES then
      break
    end
    if scanned >= M.MAX_INPUT then
      truncated = true
      break
    end
    scanned = scanned + 1
    if type(entry) == "string" then
      if needle == "" or string.find(string.lower(entry), needle, 1, true) ~= nil then
        out[#out + 1] = M.truncate_text(entry)
      end
    end
  end
  return out, { scanned = scanned, truncated = truncated }
end

return M
