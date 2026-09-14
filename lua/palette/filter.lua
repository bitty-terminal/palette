-- Bounded filtering and truncation policy for Bitty Palette
-- (bitty-terminal.palette).
--
-- Pure functions with no host dependency, so the palette policy is unit
-- testable in plain Lua. The numeric bounds mirror the bundled Rust
-- realization (`bitty-runtime/src/palette.rs`): at most `128` displayed
-- entries, a `128`-character query, and `128`-character display text per
-- entry (the host overlay text bound `MAX_OVERLAY_TEXT_LEN`).

local M = {}

M.MAX_ENTRIES = 128
M.MAX_QUERY_CHARS = 128
M.MAX_TEXT_CHARS = 128

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

-- Case-insensitive substring filter, bounded to `MAX_ENTRIES` output rows.
-- The query is truncated to `MAX_QUERY_CHARS`; non-string entries are skipped;
-- matching entry text is truncated to the overlay text bound. An empty query
-- returns the first `MAX_ENTRIES` entries unchanged in order.
function M.filter(entries, query)
  local bounded_query = char_slice(query or "", M.MAX_QUERY_CHARS)
  local needle = string.lower(bounded_query)
  local out = {}
  if type(entries) ~= "table" then
    return out
  end
  for _, entry in ipairs(entries) do
    if #out >= M.MAX_ENTRIES then
      break
    end
    if type(entry) == "string" then
      if needle == "" or string.find(string.lower(entry), needle, 1, true) ~= nil then
        out[#out + 1] = M.truncate_text(entry)
      end
    end
  end
  return out
end

return M
