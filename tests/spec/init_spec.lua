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
  options.events = options.events
    or { "focus.changed", "overlay.released", "overlay.input.available" }
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

local function explicit_catalog()
  return {
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
end

local function children(host)
  return host:session_block().component.children
end

local function query_line(host)
  return children(host)[2].text
end

local function count_line(host)
  return children(host)[3].text
end

-- Command rows are the entries after the title/query/count header. The
-- selection marker distinguishes them from typed note rows.
local function command_rows(host)
  local out = {}
  local all = children(host)
  for index = 4, #all do
    local text = all[index].text
    local prefix = string.sub(text, 1, 2)
    if prefix == "> " or prefix == "  " then
      out[#out + 1] = text
    end
  end
  return out
end

local function selected_row(host)
  local rows = command_rows(host)
  for _, row in ipairs(rows) do
    if string.sub(row, 1, 2) == "> " then
      return row
    end
  end
  return nil
end

local function scene_text(host)
  local parts = {}
  for _, child in ipairs(children(host)) do
    parts[#parts + 1] = child.text
  end
  return table.concat(parts, "\n")
end

-- Deliver one captured key event and the cold-path input nudge that makes the
-- palette drain it.
local function press(host, text, data)
  host:push_input("key", text, data)
  host:nudge_input()
end

local function type_text(host, text)
  host:push_input("text", text)
  host:nudge_input()
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
    tap.equal(#host.subscriptions, 3, "three subscriptions")
    tap.equal(host.subscriptions[1].kind, "focus.changed", "focus.changed subscribed")
    tap.equal(host.subscriptions[2].kind, "overlay.released", "overlay.released subscribed")
    tap.equal(
      host.subscriptions[3].kind,
      "overlay.input.available",
      "overlay.input.available subscribed"
    )
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
    -- interactive scene: title, live query, match count, then rows.
    local count = host:run("toggle", {})
    tap.equal(count, 3, "toggle returns filtered entry count")
    tap.ok(host.capture ~= nil, "opening acquires input capture")
    tap.equal(host.updates, 1, "opening paints the session scene once")
    tap.equal(host:session_block().component.kind, "List", "session block is a List")
    tap.equal(#children(host), 6, "session block carries header plus filtered rows")
    tap.equal(children(host)[1].text, scene.TITLE, "session block starts with title")
    tap.equal(query_line(host), "> o", "session block paints the live query")
    tap.equal(count_line(host), "3 of 3 commands", "session block paints the match count")
    tap.contains(command_rows(host)[1], "Open File", "first filtered row")
    tap.contains(command_rows(host)[3], "toggle palette", "lowercase row matched")

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
    tap.equal(#children(host), 6, "re-open repaints header plus rows")
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
    host:publish("overlay.released", { owner = "bitty-terminal.composer", reason = "cancelled" })
    tap.equal(host:run("toggle", {}), 0, "foreign overlay.released does not reset palette toggle state (palette#45)")
    tap.equal(host:run("toggle", {}), 2, "open succeeds again before own revocation")
    host:revoke_overlay()
    host:publish("overlay.released", { owner = PLUGIN_ID, reason = "focus_switched" })
    tap.equal(host:run("toggle", {}), 2, "next toggle re-opens after involuntary release")
    tap.ok(host.capture ~= nil, "re-open re-acquires input capture")
    tap.equal(#children(host), 5, "re-open paints header plus rows")
  end

  -- Opening with an empty host catalog still paints a non-empty default scene
  -- (title, query, count, and `No entries`), so a healthy-but-empty source is
  -- distinguishable from a broken one.
  do
    local host = with_grants({})
    activate(host)
    tap.equal(host:run("toggle", {}), 0, "open with no commands returns zero")
    tap.ok(host.capture ~= nil, "open with no commands still acquires capture")
    tap.equal(#children(host), 4, "empty open paints header plus placeholder")
    tap.equal(children(host)[1].text, scene.TITLE, "empty open keeps title")
    tap.equal(query_line(host), "> " .. scene.PLACEHOLDER, "empty open keeps the placeholder")
    tap.equal(count_line(host), "0 of 0 commands", "empty open counts zero commands")
    tap.equal(children(host)[4].text, scene.EMPTY_NOTE, "healthy empty catalog says No entries")
  end

  -- The palette lists the active host command catalog, not a demo list: every
  -- row `bitty.commands.list` serves (0.0.24, bitty CTX-1035) is painted, in
  -- host order, and the count the toggle returns matches.
  do
    local host = with_grants({ catalog = explicit_catalog() })
    activate(host)
    tap.equal(host:run("toggle", {}), 3, "open lists every active host command")
    tap.equal(#children(host), 6, "host catalog paints header plus one row per command")
    tap.equal(children(host)[1].text, scene.TITLE, "host catalog keeps the palette title")
    tap.equal(query_line(host), "> " .. scene.PLACEHOLDER, "host catalog starts unfiltered")
    tap.equal(count_line(host), "3 of 3 commands", "host catalog counts every command")
    tap.contains(command_rows(host)[1], "Palette: toggle", "own toggle is listed")
    tap.contains(command_rows(host)[2], "Unified Bar: focus workspace", "foreign plugin command is listed")
    tap.contains(command_rows(host)[3], "Close panel", "host action is listed")

    -- Live typing narrows the same host catalog; Backspace widens it again.
    type_text(host, "bar")
    tap.equal(query_line(host), "> bar", "typed query is painted")
    tap.equal(#command_rows(host), 1, "query narrows the host catalog to one row")
    tap.contains(command_rows(host)[1], "Unified Bar", "query keeps the matching command")
    tap.equal(count_line(host), "1 of 3 commands", "match count follows the query")
    press(host, "key:Backspace")
    tap.equal(query_line(host), "> ba", "Backspace removes one code point")
    tap.equal(#command_rows(host), 1, "partial query still matches the bar command")
    press(host, "key:Backspace")
    tap.equal(query_line(host), "> b", "second Backspace widens to one character")
    tap.equal(#command_rows(host), 3, "single-character query matches every plugin id")
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
    tap.contains(command_rows(host)[1], "alpha", "catalog row survives a fail-closed settings read")
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
    tap.equal(children(host)[4].text, scene.UNAVAILABLE_NOTE, "broken catalog paints the unavailable note")
    tap.equal(count_line(host), "0 of 0 commands", "broken catalog counts zero commands")
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
      events = { "focus.changed", "overlay.released", "overlay.input.available" },
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
    tap.equal(#children(host), 5, "last-known-good scene is kept")
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
      events = { "focus.changed", "overlay.released", "overlay.input.available" },
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
      events = { "focus.changed", "overlay.released", "overlay.input.available" },
      declared_settings = { "query" },
      catalog = catalog({ "alpha", "beta" }),
    })
    host.bitty.ui.overlay = nil
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "no-capture-table toggle returns count")
    tap.equal(host.capture, nil, "no-capture-table toggle holds no session")
    tap.equal(#host.blocks, 0, "no-capture-table toggle mounts no surface")
  end

  -- Selection moves with arrows and j/k, wrapping at both ends. j/k are
  -- navigation only while the query is empty, so a typed query can still
  -- contain them.
  do
    local host = with_grants({ catalog = explicit_catalog() })
    activate(host)
    tap.equal(host:run("toggle", {}), 3, "selection test opens three commands")
    tap.contains(selected_row(host), "Palette: toggle", "first row starts selected")
    press(host, "key:ArrowDown")
    tap.contains(selected_row(host), "Unified Bar", "ArrowDown moves the highlight")
    press(host, "key:ArrowDown")
    tap.contains(selected_row(host), "Close panel", "ArrowDown reaches the last row")
    press(host, "key:ArrowDown")
    tap.contains(selected_row(host), "Palette: toggle", "ArrowDown wraps to the first row")
    press(host, "key:ArrowUp")
    tap.contains(selected_row(host), "Close panel", "ArrowUp wraps to the last row")
    press(host, "j")
    tap.contains(selected_row(host), "Palette: toggle", "j moves down and wraps")
    press(host, "k")
    tap.contains(selected_row(host), "Close panel", "k moves up and wraps")
    type_text(host, "b")
    press(host, "j")
    tap.equal(query_line(host), "> bj", "j types once the query is non-empty")
  end

  -- The visible list is bounded to MAX_VISIBLE rows while selection can walk
  -- the full bounded match list and the window follows the highlight.
  do
    local titles = {}
    for index = 1, 20 do
      titles[index] = "command " .. tostring(index)
    end
    local host = with_grants({ catalog = catalog(titles) })
    activate(host)
    tap.equal(host:run("toggle", {}), 20, "bounded-window test opens twenty commands")
    tap.equal(#command_rows(host), 12, "visible list bounded to MAX_VISIBLE")
    for _ = 1, 12 do
      press(host, "key:ArrowDown")
    end
    tap.equal(#command_rows(host), 12, "window stays bounded after selection moves")
    tap.contains(command_rows(host)[7], "command 13", "window follows the highlight")
    tap.contains(command_rows(host)[12], "command 18", "window paints the trailing rows")
  end

  -- Enter invokes the highlighted command exactly once through the host
  -- surface and closes the overlay on success.
  do
    local host = with_grants({ catalog = explicit_catalog() })
    activate(host)
    tap.equal(host:run("toggle", {}), 3, "invoke test opens three commands")
    press(host, "key:ArrowDown")
    press(host, "key:ArrowDown")
    tap.contains(selected_row(host), "Close panel", "invoke target is highlighted")
    press(host, "key:Enter")
    tap.equal(#host.invocations, 1, "Enter invokes the command exactly once")
    tap.equal(host.invocations[1].qualified, "bitty-terminal:close", "invoked qualified id")
    tap.equal(type(host.invocations[1].args), "table", "invocation passes an args table")
    tap.equal(next(host.invocations[1].args), nil, "invocation passes empty args")
    tap.equal(host.capture, nil, "successful invocation releases the capture")
    tap.equal(#host.blocks, 0, "successful invocation destroys the surface")
    tap.equal(host:run("toggle", {}), 3, "next toggle re-opens after invocation")
  end

  -- A command whose args schema rejects the empty table is reported as a
  -- typed "Needs arguments" row; the host validates before the callee body
  -- runs, and the overlay stays open for the follow-up argument task.
  do
    local ran = false
    local host = with_grants({
      catalog = {
        {
          plugin = "test",
          id = "needs-args",
          qualified = "test:needs-args",
          title = "Needs Args",
        },
      },
      invoke_handlers = {
        ["test:needs-args"] = function(args)
          if next(args or {}) == nil then
            error(
              {
                class = "validation",
                code = "E_COMMAND_INVALID",
                message = "args do not satisfy the command schema",
              },
              0
            )
          end
          ran = true
          return true
        end,
      },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 1, "needs-args test opens one command")
    press(host, "key:Enter")
    tap.equal(#host.invocations, 1, "needs-args attempt reaches the host once")
    tap.equal(ran, false, "callee body never runs for a missing-args refusal")
    tap.ok(host.capture ~= nil, "needs-args refusal keeps the overlay open")
    tap.contains(scene_text(host), scene.NEEDS_ARGS_NOTE, "typed needs-arguments row")
    tap.contains(scene_text(host), "Needs Args", "needs-arguments row names the command")
    press(host, "key:Escape")
    tap.equal(host.capture, nil, "Escape closes the needs-args overlay")
  end

  -- A result-schema violation is also E_COMMAND_INVALID, but it happened
  -- after the callee ran, so it must not be mislabeled as missing arguments.
  do
    local host = with_grants({
      catalog = {
        {
          plugin = "test",
          id = "bad-result",
          qualified = "test:bad-result",
          title = "Bad Result",
        },
      },
      invoke_errors = {
        ["test:bad-result"] = {
          class = "validation",
          code = "E_COMMAND_INVALID",
          message = "result does not satisfy the command schema",
        },
      },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 1, "bad-result test opens one command")
    press(host, "key:Enter")
    tap.ok(host.capture ~= nil, "result-schema refusal keeps the overlay open")
    tap.contains(scene_text(host), scene.REFUSED_NOTE, "result-schema refusal is typed")
    tap.not_contains(scene_text(host), scene.NEEDS_ARGS_NOTE, "result-schema refusal is not needs-args")
  end

  -- Any other host refusal keeps the overlay open with the typed error code.
  do
    local host = with_grants({
      catalog = {
        {
          plugin = "test",
          id = "refused",
          qualified = "test:refused",
          title = "Refused",
        },
      },
      invoke_errors = {
        ["test:refused"] = {
          class = "runtime",
          code = "E_COMMAND_GONE",
          message = "command is gone",
        },
      },
    })
    activate(host)
    tap.equal(host:run("toggle", {}), 1, "refused test opens one command")
    press(host, "key:Enter")
    tap.equal(#host.invocations, 1, "refused invocation reaches the host once")
    tap.ok(host.capture ~= nil, "refused invocation keeps the overlay open")
    tap.contains(scene_text(host), scene.REFUSED_NOTE, "typed refusal row")
    tap.contains(scene_text(host), "E_COMMAND_GONE", "refusal row carries the host error code")
    press(host, "key:Escape")
    tap.equal(host.capture, nil, "Escape closes the refused overlay")
  end

  -- A host without the invocation surface reports that capability gap as a
  -- typed row instead of silently doing nothing.
  do
    local host = with_grants({ catalog = explicit_catalog() })
    activate(host)
    tap.equal(host:run("toggle", {}), 3, "no-invoke test opens three commands")
    host.bitty.commands.invoke = nil
    press(host, "key:Enter")
    tap.equal(#host.invocations, 0, "no-invoke host is never called")
    tap.ok(host.capture ~= nil, "no-invoke host keeps the overlay open")
    tap.contains(scene_text(host), scene.UNAVAILABLE_INVOKE_NOTE, "typed unavailable-invoke row")
  end

  -- A capture that dies between the nudge and the poll clears the local
  -- session instead of wedging the next toggle.
  do
    local host = with_grants({ catalog = catalog({ "alpha", "beta" }) })
    activate(host)
    tap.equal(host:run("toggle", {}), 2, "stale-session test opens")
    host:revoke_overlay()
    host:nudge_input()
    tap.equal(host:run("toggle", {}), 2, "stale session is reset and the next toggle opens")
    tap.ok(host.capture ~= nil, "re-open re-acquires input capture")
  end

  -- Downstream consumer test (palette#31, devtools#10 item 4): palette
  -- discovers all seven `bitty-featured.devtools` commands and runs each one
  -- through the host invocation seam with empty args, proving cross-plugin
  -- consumption without a live host. Loads the sibling `devtools` checkout when
  -- present in the workspace and falls back to the pinned 7-command contract in
  -- single-repo CI.
  do
    local DEVTOOLS_ID = "bitty-featured.devtools"
    local DEVTOOLS_COMMANDS = {
      { id = "plugins", title = "DevTools: list plugins" },
      { id = "commands", title = "DevTools: list commands" },
      { id = "events", title = "DevTools: list event subscriptions" },
      { id = "grants", title = "DevTools: show own grants" },
      { id = "trace-start", title = "DevTools: start event trace" },
      { id = "trace-dump", title = "DevTools: dump event trace" },
      { id = "trace-stop", title = "DevTools: stop event trace" },
    }
    local NOTIFY_MAX_CHARS = 256

    local host = with_grants({ catalog = {} })
    local foreign_bitty = host:foreign_bitty(DEVTOOLS_ID)

    local devtools_root = nil
    for _, rel in ipairs({ "/../devtools", "/../../../devtools" }) do
      local candidate = (context.root or ".") .. rel
      local probe = io.open(candidate .. "/lua/devtools/init.lua", "r")
      if probe ~= nil then
        probe:close()
        devtools_root = candidate
        break
      end
    end

    if devtools_root ~= nil then
      local saved_path = package.path
      local saved_bitty = _G.bitty
      package.path = devtools_root .. "/lua/?.lua;" .. package.path
      package.loaded["devtools.init"] = nil
      package.loaded["devtools.format"] = nil
      package.loaded["devtools.trace"] = nil
      package.loaded["devtools.view"] = nil
      _G.bitty = foreign_bitty
      require("devtools.init")
      _G.bitty = saved_bitty
      package.path = saved_path
    else
      for _, spec in ipairs(DEVTOOLS_COMMANDS) do
        foreign_bitty.commands.register({
          id = spec.id,
          title = spec.title,
          description = spec.title,
          run = function(_args)
            local summary = spec.title .. " (ok)"
            foreign_bitty.notify.show({
              title = "Bitty DevTools",
              body = summary,
              urgency = "low",
            })
            return summary
          end,
        })
      end
    end

    activate(host)
    tap.ok(#host.catalog >= #DEVTOOLS_COMMANDS, "all seven devtools commands registered in catalog")

    for index, spec in ipairs(DEVTOOLS_COMMANDS) do
      local qualified = DEVTOOLS_ID .. ":" .. spec.id
      tap.equal(
        host:run("toggle", {}),
        #host.catalog,
        "palette opens with all seven devtools commands before " .. spec.id
      )
      type_text(host, qualified)
      tap.equal(#command_rows(host), 1, "query narrows palette to " .. qualified)
      tap.contains(selected_row(host), spec.title, "selected row shows title for " .. spec.id)
      tap.contains(selected_row(host), qualified, "selected row shows qualified id for " .. spec.id)

      press(host, "key:Enter")
      tap.equal(#host.invocations, index, "Enter invokes " .. qualified .. " once")
      local call = host.invocations[index]
      tap.equal(call.qualified, qualified, "invoked qualified id matches " .. qualified)
      tap.equal(type(call.args), "table", "empty args table passed to " .. qualified)
      tap.equal(next(call.args), nil, "args table is empty for " .. qualified)
      tap.equal(type(call.result), "string", qualified .. " returns a string result")
      tap.ok(#call.result > 0, qualified .. " returns non-empty text")
      tap.equal(#host.notifications, index, qualified .. " emits exactly one notification")
      local note = host.notifications[index]
      tap.not_contains(note.body, "\n", qualified .. " notification body is single-line")
      tap.le(utf8.len(note.body), NOTIFY_MAX_CHARS, qualified .. " notification fits chrome limit")
      tap.equal(host.capture, nil, "palette closes on successful " .. qualified .. " invocation")
      tap.equal(#host.blocks, 0, "palette surface destroyed after " .. qualified)
    end
  end
end

return { run = run }
