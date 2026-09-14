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

  -- Activation registers the reserved toggle command, subscribes the declared
  -- event, and mounts the (empty) overlay block.
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

    local count = host:run("toggle", {})
    tap.equal(count, 3, "toggle returns filtered entry count")
    tap.equal(host.blocks[1].component.kind, "List", "toggled block is a List")
    tap.equal(#host.blocks[1].component.children, 3, "toggled block carries filtered rows")
    tap.equal(host.blocks[1].component.children[3].text, "toggle palette", "lowercase row matched")

    -- focus.changed while open refreshes the same block.
    local before = host.updates
    host:publish("focus.changed", {})
    tap.ok(host.updates > before, "focus.changed refreshes while toggled")

    -- focus.changed while closed is a no-op.
    host:run("toggle", {})
    tap.equal(#host.blocks[1].component.children, 0, "closing empties the block")
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

  -- Missing ui.rich fails closed at activation (mount is capability-gated).
  do
    local host = MockHost.new({
      grants = { "ui.overlay" },
      commands = { TOGGLE },
      events = { "focus.changed" },
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "missing ui.rich fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied capability code")
  end

  -- Missing ui.overlay fails closed for the overlay slot.
  do
    local host = MockHost.new({
      grants = { "ui.rich" },
      commands = { TOGGLE },
      events = { "focus.changed" },
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "missing ui.overlay fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied overlay capability code")
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
