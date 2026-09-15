-- Bounded filtering and truncation policy for Bitty Palette
-- (bitty-terminal.palette).
--
-- Pure functions with no host dependency, so the palette policy is unit
-- testable in plain Lua. The numeric bounds mirror the bundled Rust
-- realization (`bitty-runtime/src/palette.rs`): at most `128` displayed
-- entries, a `128`-character query, and `128`-character display text per
-- entry (the host overlay text bound `MAX_OVERLAY_TEXT_LEN`). The input
-- bound `MAX_INPUT` is a palette-local policy: candidate tables supplied
-- through settings are untrusted data, so a single filter pass examines at
-- most `MAX_INPUT` candidates regardless of how large the table is. No Rust
-- counterpart exists upstream (the bundled realization trusts its input).

local M = {}

M.MAX_ENTRIES = 128
M.MAX_QUERY_CHARS = 128
M.MAX_TEXT_CHARS = 128

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
