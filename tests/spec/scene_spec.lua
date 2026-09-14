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
end

return { run = run }
