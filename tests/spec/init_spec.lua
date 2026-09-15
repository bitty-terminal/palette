-- Entry-point behavior tests for `palette.init` against the mock host.

local MockHost = require("support.mock_host")

local PLUGIN_ID = "bitty-terminal.palette"
local TOGGLE = PLUGIN_ID .. ":toggle"

local function activate(host)
  _G.bitty = host.bitty
  package.loaded["palette.init"] = nil
  package.loaded["palette.filter"] = nil
  package.loaded["palette.scene"] = nil
  return require("palette.init")
end

local function with_grants(options)
  options.grants = options.grants or { "ui.rich", "ui.overlay" }
  options.commands = options.commands or { TOGGLE }
  options.events = options.events or { "focus.changed" }
  return MockHost.new(options)
end

local function run(context)
  local tap = context.tap

  -- Activation registers the reserved toggle command with closed argument and
  -- result schemas, subscribes the declared event, and mounts the (empty)
  -- overlay block.
  do
    local host = with_grants({
      settings = {
        entries = { "Open File", "Close Tab", "toggle palette" },
        query = "o",
      },
    })
    activate(host)
    tap.ok(host.commands[TOGGLE] ~= nil, "toggle command registered")
    tap.equal(#host.subscriptions, 1, "one subscription")
    tap.equal(host.subscriptions[1].kind, "focus.changed", "focus.changed subscribed")
    tap.equal(#host.blocks, 1, "overlay block mounted at activation")
    tap.equal(host.blocks[1].component.kind, "List", "mounted block is a List")
    tap.equal(#host.blocks[1].component.children, 0, "mounted block starts empty")

    -- The command contract declares closed object arguments and the integer
    -- count the body returns.
    local def = host.commands[TOGGLE]
    local args_schema = def.args_schema or {}
    local result_schema = def.result_schema or {}
    tap.equal(type(def.args_schema), "table", "toggle declares an args schema")
    tap.equal(args_schema.type, "object", "toggle args schema is an object")
    tap.equal(args_schema.additionalProperties, false, "toggle args schema is closed")
    tap.equal(next(args_schema.properties or {}), nil, "toggle args schema declares no properties")
    tap.equal(type(def.result_schema), "table", "toggle declares a result schema")
    tap.equal(result_schema.type, "integer", "toggle result schema is an integer")
    tap.equal(result_schema.minimum, 0, "toggle result schema is non-negative")

    local count = host:run("toggle", {})
    tap.equal(count, 3, "toggle returns filtered entry count")
    tap.equal(host.updates, 1, "opening renders the filtered list once")
    tap.equal(host.blocks[1].component.kind, "List", "toggled block is a List")
    tap.equal(#host.blocks[1].component.children, 3, "toggled block carries filtered rows")
    tap.equal(host.blocks[1].component.children[3].text, "toggle palette", "lowercase row matched")

    -- focus.changed while open refreshes the same block.
    local before = host.updates
    host:publish("focus.changed", {})
    tap.ok(host.updates > before, "focus.changed refreshes while toggled")

    -- Closing renders the empty scene exactly once and reports no entries.
    local closing = host.updates
    tap.equal(host:run("toggle", {}), 0, "closing reports no displayed entries")
    tap.equal(host.updates, closing + 1, "closing renders exactly once")
    tap.equal(#host.blocks[1].component.children, 0, "closing empties the block")

    -- focus.changed while closed is a no-op.
    local closed_updates = host.updates
    host:publish("focus.changed", {})
    tap.equal(host.updates, closed_updates, "focus.changed is a no-op while closed")
  end

  -- Undeclared event fails closed at activation.
  do
    local host = MockHost.new({
      grants = { "ui.rich", "ui.overlay" },
      commands = { TOGGLE },
      events = {},
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "undeclared event fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_EVENT_UNDECLARED", "undeclared event code")
  end

  -- Missing ui.rich (mount denied) degrades to command-only mode instead of
  -- crashing activation.
  do
    local host = MockHost.new({
      grants = { "ui.overlay" },
      commands = { TOGGLE },
      events = { "focus.changed" },
      settings = { entries = { "alpha", "beta" } },
    })
    local ok = pcall(activate, host)
    tap.ok(ok, "denied mount does not crash activation")
    tap.ok(host.commands[TOGGLE] ~= nil, "denied mount still registers toggle")
    tap.equal(#host.blocks, 0, "denied mount leaves no block")
    tap.equal(host:run("toggle", {}), 2, "denied mount toggle returns count")
  end

  -- Missing ui.overlay (slot denied) degrades the same way.
  do
    local host = MockHost.new({
      grants = { "ui.rich" },
      commands = { TOGGLE },
      events = { "focus.changed" },
      settings = { entries = { "alpha" } },
    })
    local ok = pcall(activate, host)
    tap.ok(ok, "denied overlay slot does not crash activation")
    tap.ok(host.commands[TOGGLE] ~= nil, "denied overlay slot still registers toggle")
    tap.equal(#host.blocks, 0, "denied overlay slot leaves no block")
    tap.equal(host:run("toggle", {}), 1, "denied overlay slot toggle returns count")
  end

  -- A grant revoked after activation makes updates fail; the failure is
  -- swallowed and the last successfully presented scene is kept.
  do
    local host = with_grants({
      settings = { entries = { "alpha", "beta" } },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "open succeeds before revocation")
    tap.equal(host.updates, 1, "first render succeeded")
    host.grants["ui.rich"] = nil
    tap.equal(host:run("toggle", {}), 0, "closing after revocation does not throw")
    tap.equal(host.updates, 1, "rejected close update is swallowed")
    tap.equal(host:run("toggle", {}), 2, "reopen after revocation returns count")
    tap.equal(host.updates, 1, "rejected open update is swallowed")
    host:publish("focus.changed", {})
    tap.equal(host.updates, 1, "rejected focus refresh is swallowed")
    tap.equal(#host.blocks[1].component.children, 2, "last-known-good scene is kept")
  end

  -- Degraded mode: a host bridge without `bitty.ui` still registers the
  -- command and returns the filtered count.
  do
    local host = MockHost.new({
      grants = {},
      commands = { TOGGLE },
      events = { "focus.changed" },
      settings = { entries = { "alpha", "beta" } },
    })
    host.bitty.ui = nil
    activate(host)
    tap.ok(host.commands[TOGGLE] ~= nil, "degraded mode registers toggle")
    tap.equal(host:run("toggle", {}), 2, "degraded toggle returns count")
    tap.equal(#host.blocks, 0, "degraded mode mounts no block")
  end
end

return { run = run }
