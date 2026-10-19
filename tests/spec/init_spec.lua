-- Entry-point behavior tests for `palette.init` against the mock host.

local MockHost = require("support.mock_host")
local scene = require("palette.scene")

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
  options.grants = options.grants or { "ui.overlay.focus" }
  options.commands = options.commands or { TOGGLE }
  options.events = options.events or { "focus.changed", "overlay.released" }
  options.declared_settings = options.declared_settings or { "query" }
  return MockHost.new(options)
end

-- Catalog rows shaped like `bitty.commands.list` (bitty CTX-1035).
local function catalog(titles)
  local rows = {}
  for index, title in ipairs(titles) do
    rows[index] = {
      plugin = "test",
      id = "cmd" .. index,
      qualified = "test:cmd" .. index,
      title = title,
    }
  end
  return rows
end

local function run(context)
  local tap = context.tap

  -- Activation registers the reserved toggle command with closed argument and
  -- result schemas and subscribes the declared events. Nothing is mounted:
  -- every open acquires a fresh session surface.
  do
    local host = with_grants({
      catalog = catalog({ "Open File", "Close Tab", "toggle palette" }),
      settings = { query = "o" },
    })
    activate(host)
    tap.ok(host.commands[TOGGLE] ~= nil, "toggle command registered")
    tap.equal(#host.subscriptions, 2, "two subscriptions")
    tap.equal(host.subscriptions[1].kind, "focus.changed", "focus.changed subscribed")
    tap.equal(host.subscriptions[2].kind, "overlay.released", "overlay.released subscribed")
    tap.equal(#host.blocks, 0, "activation mounts no block")
    tap.equal(host.capture, nil, "activation holds no capture")

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

    -- Opening acquires the transient input capture (W-01) and paints the
    -- default scene with title plus filtered rows.
    local count = host:run("toggle", {})
    tap.equal(count, 3, "toggle returns filtered entry count")
    tap.ok(host.capture ~= nil, "opening acquires input capture")
    tap.equal(host.updates, 1, "opening paints the session scene once")
    tap.equal(host:session_block().component.kind, "List", "session block is a List")
    tap.equal(#host:session_block().component.children, 4, "session block carries title plus filtered rows")
    tap.equal(host:session_block().component.children[1].text, "Palette", "session block starts with title")
    tap.equal(host:session_block().component.children[4].text, "toggle palette", "lowercase row matched")

    -- focus.changed while open refreshes the same session block.
    local before = host.updates
    host:publish("focus.changed", {})
    tap.ok(host.updates > before, "focus.changed refreshes while toggled")

    -- Closing releases the capture and destroys the session surface.
    tap.equal(host:run("toggle", {}), 0, "closing reports no displayed entries")
    tap.equal(host.capture, nil, "closing releases input capture")
    tap.equal(#host.blocks, 0, "closing destroys the session surface")

    -- focus.changed while closed is a no-op.
    local closed_updates = host.updates
    host:publish("focus.changed", {})
    tap.equal(host.updates, closed_updates, "focus.changed is a no-op while closed")

    -- Re-opening acquires a fresh session after a close.
    tap.equal(host:run("toggle", {}), 3, "re-open returns filtered entry count")
    tap.ok(host.capture ~= nil, "re-open re-acquires input capture")
    tap.equal(#host:session_block().component.children, 4, "re-open repaints title plus rows")
  end

  -- An involuntary session end observed through `overlay.released` resets the
  -- toggle state, so the next toggle re-opens instead of closing a surface
  -- that is already gone.
  do
    local host = with_grants({
      catalog = catalog({ "alpha", "beta" }),
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "open succeeds before revocation")
    tap.ok(host.capture ~= nil, "capture held while open")
    host:revoke_overlay()
    tap.equal(#host.blocks, 0, "revocation destroys the session surface")
    host:publish("overlay.released", { owner = PLUGIN_ID, reason = "focus_switched" })
    tap.equal(host:run("toggle", {}), 2, "next toggle re-opens after involuntary release")
    tap.ok(host.capture ~= nil, "re-open re-acquires input capture")
    tap.equal(#host:session_block().component.children, 3, "re-open paints title plus rows")
  end

  -- Opening with an empty host catalog still paints a non-empty default scene
  -- (title plus `No entries`), so a healthy-but-empty source is distinguishable
  -- from a broken one.
  do
    local host = with_grants({})
    activate(host)
    tap.equal(host:run("toggle", {}), 0, "open with no commands returns zero")
    tap.ok(host.capture ~= nil, "open with no commands still acquires capture")
    tap.equal(#host:session_block().component.children, 2, "empty open paints title plus placeholder")
    tap.equal(host:session_block().component.children[1].text, "Palette", "empty open keeps title")
    tap.equal(
      host:session_block().component.children[2].text,
      scene.EMPTY_NOTE,
      "healthy empty catalog says No entries"
    )
  end

  -- The palette lists the active host command catalog, not a demo list: every
  -- row `bitty.commands.list` serves (0.0.24, bitty CTX-1035) is painted, in
  -- host order, and the count the toggle returns matches.
  do
    local host = with_grants({
      catalog = {
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
      },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 3, "open lists every active host command")
    local children = host:session_block().component.children
    tap.equal(#children, 4, "host catalog paints title plus one row per command")
    tap.equal(children[1].text, scene.TITLE, "host catalog keeps the palette title")
    tap.equal(children[2].text, "Palette: toggle", "own toggle is listed")
    tap.equal(children[3].text, "Unified Bar: focus workspace", "foreign plugin command is listed")
    tap.equal(children[4].text, "Close panel", "host action is listed")

    -- A query narrows the same host catalog; it does not replace the source.
    host.settings.query = "bar"
    host:publish("focus.changed", {})
    local filtered = host:session_block().component.children
    tap.equal(#filtered, 2, "query narrows the host catalog to one row")
    tap.equal(filtered[2].text, "Unified Bar: focus workspace", "query keeps the matching command")
  end

  -- The host catalog is the entry source, so a host that fails closed on the
  -- (now declared) query key cannot empty the palette the way undeclared
  -- `entries` did before issue #36.
  do
    local host = with_grants({
      declared_settings = {},
      catalog = catalog({ "alpha" }),
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 1, "undeclared query does not empty the catalog")
    tap.equal(
      host:session_block().component.children[2].text,
      "alpha",
      "catalog row survives a fail-closed settings read"
    )
  end

  -- A catalog the host cannot serve is reported as unavailable, never as an
  -- empty catalog: the overlay note differs and the toggle still degrades to a
  -- count instead of throwing at the caller.
  do
    local host = with_grants({
      catalog = { { title = "must not be painted" } },
      catalog_error = { class = "runtime", code = "E_NOT_IMPLEMENTED" },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 0, "broken catalog returns zero")
    tap.ok(host.capture ~= nil, "broken catalog still opens the surface")
    tap.equal(
      host:session_block().component.children[2].text,
      scene.UNAVAILABLE_NOTE,
      "broken catalog paints the unavailable note"
    )
    tap.ok(
      scene.UNAVAILABLE_NOTE ~= scene.EMPTY_NOTE,
      "broken and empty sources stay distinguishable"
    )
  end

  -- Undeclared event fails closed at activation.
  do
    local host = MockHost.new({
      grants = { "ui.overlay.focus" },
      commands = { TOGGLE },
      events = {},
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "undeclared event fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_EVENT_UNDECLARED", "undeclared event code")
  end

  -- Missing ui.overlay.focus (capture denied) degrades to command-only mode
  -- instead of crashing activation: counts are still returned, no surface.
  do
    local host = MockHost.new({
      grants = {},
      commands = { TOGGLE },
      events = { "focus.changed", "overlay.released" },
      declared_settings = { "query" },
      catalog = catalog({ "alpha", "beta" }),
    })
    local ok = pcall(activate, host)
    tap.ok(ok, "denied capture does not crash activation")
    tap.ok(host.commands[TOGGLE] ~= nil, "denied capture still registers toggle")
    tap.equal(host:run("toggle", {}), 2, "denied capture toggle returns count")
    tap.equal(host.capture, nil, "denied capture holds no session")
    tap.equal(#host.blocks, 0, "denied capture mounts no surface")
    tap.equal(host:run("toggle", {}), 0, "denied capture close returns zero")
  end

  -- A grant revoked after activation makes updates fail; the failure is
  -- swallowed and the last successfully presented scene is kept.
  do
    local host = with_grants({
      catalog = catalog({ "alpha", "beta" }),
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "open succeeds before revocation")
    tap.equal(host.updates, 1, "first paint succeeded")
    host.grants["ui.overlay.focus"] = nil
    host:publish("focus.changed", {})
    tap.equal(host.updates, 1, "rejected focus refresh is swallowed")
    tap.equal(#host:session_block().component.children, 3, "last-known-good scene is kept")
    tap.equal(host:run("toggle", {}), 0, "closing after revocation does not throw")
    tap.equal(host.capture, nil, "close still ends the session without the grant")
    tap.equal(#host.blocks, 0, "close still destroys the surface without the grant")
    tap.equal(host:run("toggle", {}), 2, "reopen after revocation returns count")
    tap.equal(host.capture, nil, "reopen after revocation holds no session")
  end

  -- A live foreign session fails the acquire; the toggle degrades to a
  -- command-only open instead of throwing, and a later close is a no-op.
  do
    local host = with_grants({
      catalog = catalog({ "alpha", "beta" }),
    })
    activate(host)
    host.capture = { handle = -1 }
    tap.equal(host:run("toggle", {}), 2, "conflicted open returns count")
    tap.equal(#host.blocks, 0, "conflicted open mounts no surface")
    tap.equal(host:run("toggle", {}), 0, "close after conflict returns zero")
  end

  -- Degraded mode: a host bridge without `bitty.ui` still registers the
  -- command and returns the filtered count.
  do
    local host = MockHost.new({
      grants = {},
      commands = { TOGGLE },
      events = { "focus.changed", "overlay.released" },
      declared_settings = { "query" },
      catalog = catalog({ "alpha", "beta" }),
    })
    host.bitty.ui = nil
    activate(host)
    tap.ok(host.commands[TOGGLE] ~= nil, "degraded mode registers toggle")
    tap.equal(host:run("toggle", {}), 2, "degraded toggle returns count")
    tap.equal(#host.blocks, 0, "degraded mode mounts no surface")
  end

  -- Degraded mode: a host bridge with v1 UI but no W-01 capture table counts
  -- without acquiring, instead of throwing at the toggle caller.
  do
    local host = MockHost.new({
      grants = { "ui.overlay.focus" },
      commands = { TOGGLE },
      events = { "focus.changed", "overlay.released" },
      declared_settings = { "query" },
      catalog = catalog({ "alpha", "beta" }),
    })
    host.bitty.ui.overlay = nil
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "no-capture-table toggle returns count")
    tap.equal(host.capture, nil, "no-capture-table toggle holds no session")
    tap.equal(#host.blocks, 0, "no-capture-table toggle mounts no surface")
  end
end

return { run = run }
