-- Unit tests for `palette.scene` (declarative overlay composition).

local function run(context)
  local tap = context.tap
  local scene = require("palette.scene")

  local node = scene.list({ "one", "two" })
  tap.equal(node.kind, "List", "list node kind")
  tap.equal(#node.children, 2, "list child count")
  tap.equal(node.children[1].kind, "Text", "child node kind")
  tap.equal(node.children[1].text, "one", "child text")
  tap.equal(node.children[2].text, "two", "second child text")

  local empty = scene.empty()
  tap.equal(empty.kind, "List", "empty node kind")
  tap.equal(#empty.children, 0, "empty node has no children")

  -- The default open scene is never empty: a title row plus either the
  -- filtered items or a placeholder row, so the surfaced overlay always
  -- paints a real UI instead of a bare pill.
  local bare = scene.default({})
  tap.equal(bare.kind, "List", "default node kind")
  tap.ok(#bare.children >= 2, "default scene is non-empty without entries")
  tap.equal(bare.children[1].kind, "Text", "default title node kind")
  tap.equal(bare.children[1].text, scene.TITLE, "default title text")

  local full = scene.default({ "one", "two" })
  tap.equal(#full.children, 3, "default scene carries title plus items")
  tap.equal(full.children[2].text, "one", "default first item")
  tap.equal(full.children[3].text, "two", "default second item")
  for _, child in ipairs(full.children) do
    tap.equal(child.kind, "Text", "default scene uses Text rows only")
  end

  -- A broken catalog is distinguishable from a healthy empty one.
  local unavailable = scene.default({}, false)
  tap.equal(
    unavailable.children[2].text,
    scene.UNAVAILABLE_NOTE,
    "unavailable source paints its own note"
  )
  tap.ok(scene.UNAVAILABLE_NOTE ~= scene.EMPTY_NOTE, "unavailable and empty notes differ")

  -- The interactive view adds the live query and match-count header, then the
  -- visible rows.
  local view = scene.view({
    rows = { "> one  test:one", "  two  test:two" },
    query = "o",
    matched = 2,
    total = 5,
  })
  tap.equal(view.kind, "List", "view node kind")
  tap.equal(view.children[1].text, scene.TITLE, "view title")
  tap.equal(view.children[2].text, "> o", "view paints the live query")
  tap.equal(view.children[3].text, "2 of 5 commands", "view paints the match count")
  tap.equal(view.children[4].text, "> one  test:one", "view paints the selected row")
  tap.equal(view.children[5].text, "  two  test:two", "view paints the unselected row")
  for _, child in ipairs(view.children) do
    tap.equal(child.kind, "Text", "view uses Text rows only")
  end

  -- Empty query uses the placeholder hint; a typed note row appears between
  -- the header and the rows.
  local placeholder = scene.view({ rows = {}, query = "", matched = 0, total = 0 })
  tap.equal(placeholder.children[2].text, "> " .. scene.PLACEHOLDER, "empty query placeholder")
  local noted = scene.view({
    rows = { "> one  test:one" },
    query = "o",
    matched = 1,
    total = 1,
    note = scene.NEEDS_ARGS_NOTE .. ": one",
  })
  tap.equal(noted.children[4].text, scene.NEEDS_ARGS_NOTE .. ": one", "typed note row")
  tap.equal(noted.children[5].text, "> one  test:one", "rows follow the note row")

  -- A no-match view uses its own placeholder instead of the empty-catalog
  -- note.
  local no_match = scene.view({
    rows = {},
    query = "zzz",
    matched = 0,
    total = 3,
    empty_note = scene.NO_MATCH_NOTE,
  })
  tap.equal(no_match.children[4].text, scene.NO_MATCH_NOTE, "no-match placeholder")
  tap.ok(scene.NO_MATCH_NOTE ~= scene.EMPTY_NOTE, "no-match and empty notes differ")

  -- Every painted row respects the overlay text bound.
  local long_row = string.rep("x", 300)
  local truncated = scene.view({ rows = { long_row }, query = "", matched = 1, total = 1 })
  tap.equal(#truncated.children[4].text, 128, "view truncates long rows")

  -- The selection marker and qualified id are part of the row text.
  tap.equal(scene.row_text("Title", "owner:id", true), "> Title  owner:id", "selected row text")
  tap.equal(scene.row_text("Title", "owner:id", false), "  Title  owner:id", "idle row text")
end

return { run = run }
