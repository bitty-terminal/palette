-- Unit tests for `palette.filter` (bounded filtering/truncation policy).

local function run(context)
  local tap = context.tap
  local filter = require("palette.filter")

  -- Output/query/text bounds mirror the bundled Rust realization; the input
  -- bound is the palette-local untrusted-input policy.
  tap.equal(filter.MAX_ENTRIES, 128, "MAX_ENTRIES")
  tap.equal(filter.MAX_QUERY_CHARS, 128, "MAX_QUERY_CHARS")
  tap.equal(filter.MAX_TEXT_CHARS, 128, "MAX_TEXT_CHARS")
  tap.equal(filter.MAX_INPUT, 1024, "MAX_INPUT")

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

  -- Non-table input fails closed to an empty list with zeroed stats.
  local nil_out, nil_stats = filter.filter(nil, "x")
  tap.equal(#nil_out, 0, "nil entries yields empty list")
  tap.equal(nil_stats.scanned, 0, "nil entries scans nothing")
  tap.equal(nil_stats.truncated, false, "nil entries is not truncation")
  local string_out, string_stats = filter.filter("not a table", "x")
  tap.equal(#string_out, 0, "string entries yields empty list")
  tap.equal(string_stats.scanned, 0, "string entries scans nothing")
  tap.equal(string_stats.truncated, false, "string entries is not truncation")

  -- Output is bounded to MAX_ENTRIES.
  local many = {}
  for index = 1, 300 do
    many[index] = "entry-" .. tostring(index)
  end
  local bounded, bounded_stats = filter.filter(many, "")
  tap.equal(#bounded, filter.MAX_ENTRIES, "output bounded to MAX_ENTRIES")
  tap.equal(bounded_stats.scanned, filter.MAX_ENTRIES, "output bound stops the scan before MAX_INPUT")

  -- Ten-thousand-candidate input is bounded by MAX_INPUT: candidates past the
  -- bound are never examined, and the cut is recorded in the stats. The match
  -- below sits past the bound, so finding it would prove an unbounded scan.
  local oversized = {}
  for index = 1, 10000 do
    oversized[index] = "entry-" .. tostring(index)
  end
  oversized[filter.MAX_INPUT + 1] = "needle-past-bound"
  local oversized_out, oversized_stats = filter.filter(oversized, "needle")
  tap.equal(#oversized_out, 0, "candidates past MAX_INPUT are not examined")
  tap.equal(oversized_stats.scanned, filter.MAX_INPUT, "scan work is bounded to MAX_INPUT")
  tap.equal(oversized_stats.truncated, true, "oversized input records truncation")
  local oversized_all, oversized_all_stats = filter.filter(oversized, "")
  tap.equal(#oversized_all, filter.MAX_ENTRIES, "oversized input still honors the output bound")
  tap.equal(oversized_all_stats.truncated, false, "output bound is not input truncation")

  -- Exactly MAX_INPUT candidates are fully scanned without a truncation bit.
  local exact = {}
  for index = 1, filter.MAX_INPUT do
    exact[index] = "no-match"
  end
  local exact_out, exact_stats = filter.filter(exact, "absent")
  tap.equal(#exact_out, 0, "exact-bound input has no matches")
  tap.equal(exact_stats.scanned, filter.MAX_INPUT, "exact-bound input is fully scanned")
  tap.equal(exact_stats.truncated, false, "exact-bound input is not truncated")

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
