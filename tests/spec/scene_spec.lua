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
end

return { run = run }
