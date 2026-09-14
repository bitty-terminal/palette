-- Unit tests for `palette.filter` (bounded filtering/truncation policy).

local function run(context)
  local tap = context.tap
  local filter = require("palette.filter")

  -- Bounds mirror the bundled Rust realization.
  tap.equal(filter.MAX_ENTRIES, 128, "MAX_ENTRIES")
  tap.equal(filter.MAX_QUERY_CHARS, 128, "MAX_QUERY_CHARS")
  tap.equal(filter.MAX_TEXT_CHARS, 128, "MAX_TEXT_CHARS")

  -- Case-insensitive substring filtering.
  local entries = { "Open File", "Close Tab", "toggle palette", "Reload" }
  local matched = filter.filter(entries, "open")
  tap.equal(#matched, 1, "case-insensitive substring match count")
  tap.equal(matched[1], "Open File", "uppercase entry matched by lowercase query")
  local palette_match = filter.filter(entries, "palette")
  tap.equal(#palette_match, 1, "substring match count for palette")
  tap.equal(palette_match[1], "toggle palette", "lowercase entry matched")

  -- Empty query returns entries unchanged in order.
  local all = filter.filter(entries, "")
  tap.equal(#all, 4, "empty query returns all entries")
  tap.equal(all[2], "Close Tab", "empty query preserves order")

  -- Non-string entries are skipped.
  local mixed = filter.filter({ "alpha", 42, true, "beta" }, "")
  tap.equal(#mixed, 2, "non-string entries skipped")

  -- Non-table input fails closed to an empty list.
  tap.equal(#filter.filter(nil, "x"), 0, "nil entries yields empty list")

  -- Output is bounded to MAX_ENTRIES.
  local many = {}
  for index = 1, 300 do
    many[index] = "entry-" .. tostring(index)
  end
  local bounded = filter.filter(many, "")
  tap.equal(#bounded, filter.MAX_ENTRIES, "output bounded to MAX_ENTRIES")

  -- Query is truncated to MAX_QUERY_CHARS before matching.
  local long_query = string.rep("a", 200)
  tap.equal(#filter.filter({ "b" }, long_query), 0, "truncated long query does not match")

  -- Multi-byte truncation never splits a code point.
  local multibyte = string.rep("é", 200)
  local truncated = filter.truncate_text(multibyte)
  tap.equal(filter.char_count(truncated), filter.MAX_TEXT_CHARS, "multibyte truncation char count")
  tap.ok(utf8.len(truncated) ~= nil, "truncated text remains valid UTF-8")

  -- Long ASCII text truncates at the bound.
  local ascii = string.rep("x", 300)
  tap.equal(#filter.truncate_text(ascii), filter.MAX_TEXT_CHARS, "ASCII text truncates at bound")

  -- Matching text is truncated in the output.
  local long_entry = string.rep("y", 300)
  local truncated_match = filter.filter({ long_entry }, "")
  tap.equal(#truncated_match[1], filter.MAX_TEXT_CHARS, "matched text truncated")
end

return { run = run }
