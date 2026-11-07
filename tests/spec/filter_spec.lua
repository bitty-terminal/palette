-- Unit tests for `palette.filter` (bounded filtering/truncation policy).

local function run(context)
  local tap = context.tap
  local filter = require("palette.filter")

  -- Output/query/text bounds are this plugin's envelope (carried over from
  -- the removed bundled Rust realization); the input bound is the
  -- palette-local untrusted-input policy.
  tap.equal(filter.MAX_ENTRIES, 128, "MAX_ENTRIES")
  tap.equal(filter.MAX_VISIBLE, 12, "MAX_VISIBLE")
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

  -- Command-catalog filtering normalizes rows and matches id, title, and
  -- owning plugin id case-insensitively.
  local rows = {
    {
      plugin = "bitty-terminal.palette",
      id = "toggle",
      qualified = "bitty-terminal.palette:toggle",
      title = "Palette: toggle",
    },
    {
      plugin = "bitty-terminal.bar",
      id = "focus",
      qualified = "bitty-terminal.bar:focus",
      title = "Unified Bar: focus workspace",
    },
    {
      plugin = "bitty-terminal",
      id = "close",
      qualified = "bitty-terminal:close",
      title = "Close panel",
    },
  }
  local by_title, title_stats = filter.filter_commands(rows, "close")
  tap.equal(#by_title, 1, "command filter matches the title")
  tap.equal(by_title[1].qualified, "bitty-terminal:close", "title match keeps the qualified id")
  tap.equal(title_stats.scanned, 3, "command filter scans every row")
  tap.equal(title_stats.matched, 1, "command filter reports the match count")
  tap.equal(title_stats.truncated, false, "command filter is not truncated")

  local by_id = filter.filter_commands(rows, "focus")
  tap.equal(#by_id, 1, "command filter matches the plugin-local id")
  tap.equal(by_id[1].id, "focus", "id match keeps the row id")

  local by_plugin = filter.filter_commands(rows, "BAR")
  tap.equal(#by_plugin, 1, "command filter matches the plugin id case-insensitively")
  tap.equal(by_plugin[1].plugin, "bitty-terminal.bar", "plugin match keeps the owner id")

  local empty_query, empty_stats = filter.filter_commands(rows, "")
  tap.equal(#empty_query, 3, "empty command query returns every row")
  tap.equal(empty_stats.matched, 3, "empty command query counts every row")

  local none, none_stats = filter.filter_commands(rows, "absent")
  tap.equal(#none, 0, "absent query matches nothing")
  tap.equal(none_stats.matched, 0, "absent query reports zero matches")

  -- Non-table input fails closed; malformed rows are skipped; a plain string
  -- row is still normalized for compatibility with a legacy catalog.
  local nil_rows, nil_row_stats = filter.filter_commands(nil, "x")
  tap.equal(#nil_rows, 0, "nil command rows yield an empty list")
  tap.equal(nil_row_stats.scanned, 0, "nil command rows scan nothing")
  local malformed = filter.filter_commands({ 42, true, { title = "" } }, "")
  tap.equal(#malformed, 0, "malformed command rows are skipped")
  local string_rows = filter.filter_commands({ "legacy row" }, "legacy")
  tap.equal(#string_rows, 1, "string command rows are normalized")
  tap.equal(string_rows[1].title, "legacy row", "string command row keeps its text")

  -- The command output is bounded to MAX_ENTRIES while the match count keeps
  -- counting inside the bounded scan.
  local many_rows = {}
  for index = 1, 300 do
    many_rows[index] = {
      plugin = "test",
      id = "cmd" .. tostring(index),
      qualified = "test:cmd" .. tostring(index),
      title = "entry-" .. tostring(index),
    }
  end
  local bounded_rows, bounded_row_stats = filter.filter_commands(many_rows, "")
  tap.equal(#bounded_rows, filter.MAX_ENTRIES, "command output bounded to MAX_ENTRIES")
  tap.equal(bounded_row_stats.matched, filter.MAX_ENTRIES, "command match count follows the output bound")
  tap.equal(bounded_row_stats.scanned, 300, "command scan covers the whole bounded input")

  -- Backspace removes one code point, including a multi-byte character.
  tap.equal(filter.drop_last_char("abc"), "ab", "drop_last_char removes one ASCII character")
  tap.equal(filter.drop_last_char("a"), "", "drop_last_char removes the last character")
  tap.equal(filter.drop_last_char(""), "", "drop_last_char on empty text")
  tap.equal(filter.drop_last_char("é"), "", "drop_last_char removes a multi-byte character")
  tap.equal(filter.drop_last_char("aé"), "a", "drop_last_char keeps the leading character")
  tap.equal(filter.truncate_query(string.rep("q", 200)), string.rep("q", filter.MAX_QUERY_CHARS), "query truncation bound")
end

return { run = run }
