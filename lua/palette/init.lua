-- Entry point for Bitty Palette (bitty-terminal.palette).
--
-- The host evaluates this file once per plugin activation and owns every
-- resource created here for the lifetime of that generation. Registration
-- calls (`bitty.commands.register`, `bitty.events.subscribe`) are valid only
-- while this file executes.
--
-- Accepted surface: Plugin API v1 Lua Surface RFC (ADR 0009) plus the accepted
-- W-01 overlay-input-capture contract (capability `ui.overlay.focus`,
-- `bitty.ui.overlay.*`). The palette holds no retained UI block: every open
-- acquires the focusable overlay and its capture session in one Core-owned
-- switch from a presentation-hint spec (`title`, `placeholder`), paints the
-- interactive scene (title, live query, match count, selected command rows)
-- with the session-owned update, and destroys the surface on release. The
-- Core surfaces only the capture owner's block, so the acquire is what makes
-- the overlay visible; without it the toggle degrades to command-only counts.
--
-- Entry source: `bitty.commands.list` serves the active host command catalog
-- on 0.0.24 (bitty CTX-1035), so the palette lists the host commands and
-- actions it exists to pick instead of a privately populated settings list.
-- Captured keystrokes arrive on the cold path: the host publishes the
-- observation-only `overlay.input.available` nudge while this session owns
-- queued input, and the palette drains it through `bitty.ui.overlay.poll`.
-- The bounded `query` setting seeds the filter at open; live typing then owns
-- the query for the session.
--
-- Invocation is host-mediated: Enter calls `bitty.commands.invoke(qualified,
-- {})`, so the host keeps its deny-by-default dispatch, args validation, and
-- cross-VM containment. The palette never re-implements dispatch. A command
-- whose args schema rejects the empty argument table fails with
-- `E_COMMAND_INVALID` before its body runs; the palette reports that as a
-- typed "Needs arguments" row and keeps the overlay open (the argument editor
-- is a separate task, bitty#2965). Any other refusal keeps the overlay open
-- with the typed host error code.
--
-- Every host call is guarded: a host without the capture table, a denied
-- focus grant, or a live foreign session (`E_UI_ALREADY_CAPTURED`) degrades
-- to command-only counts instead of throwing at the toggle caller, and a
-- rejected update keeps the last successfully presented scene instead of
-- propagating to the command caller or event dispatcher.

local filter = require("palette.filter")
local scene = require("palette.scene")

local M = {}

local toggled = false
-- Session handle returned by `bitty.ui.overlay.acquire` while open, nil when
-- closed. The Core destroys the spec surface on release, so every open
-- acquires a fresh handle and nothing is retained across toggles.
local session = nil
-- Live filter text for the current session, seeded from the `query` setting.
local query = ""
-- One-based index into the filtered command list.
local selected = 1
-- Typed refusal/needs-arguments row for the current interaction, or nil.
local note = nil

local function setting(name)
  local settings = bitty.settings
  if type(settings) ~= "table" or type(settings.get) ~= "function" then
    return nil
  end
  local ok, value = pcall(settings.get, name)
  if ok then
    return value
  end
  return nil
end

local function initial_query()
  local value = setting("query")
  if type(value) == "string" then
    return value
  end
  return ""
end

-- Active host command catalog rows plus a source flag. The flag is what lets
-- the scene distinguish a genuinely empty catalog from a host that cannot
-- serve one at all: a missing bridge, a raised call, or a non-table result
-- reports `false`, never a silently empty list. Rows stay untrusted data
-- until `filter.filter_commands` normalizes and bounds them.
local function catalog()
  local commands = bitty.commands
  if type(commands) ~= "table" or type(commands.list) ~= "function" then
    return {}, false
  end
  local ok, rows = pcall(commands.list)
  if not ok or type(rows) ~= "table" then
    return {}, false
  end
  return rows, true
end

-- The filtered view for the live query: normalized rows, filter stats, and the
-- catalog source flag.
local function current_view()
  local rows, source_ok = catalog()
  local entries, stats = filter.filter_commands(rows, query)
  return entries, stats, source_ok
end

local function clamp_selection(total)
  if total <= 0 then
    selected = 1
    return
  end
  if selected < 1 then
    selected = 1
  end
  if selected > total then
    selected = total
  end
end

-- Visible slice of the matched list, kept centered on the selection while
-- never exceeding the bounded `MAX_VISIBLE` row count.
local function visible_window(total)
  if total <= filter.MAX_VISIBLE then
    return 1, total
  end
  local half = math.floor(filter.MAX_VISIBLE / 2)
  local first = selected - half
  if first < 1 then
    first = 1
  end
  local max_first = total - filter.MAX_VISIBLE + 1
  if first > max_first then
    first = max_first
  end
  return first, first + filter.MAX_VISIBLE - 1
end

-- Compose the interactive scene for the current query and selection. Returns
-- the scene node plus the matched entry list.
local function build_scene()
  local entries, stats, source_ok = current_view()
  clamp_selection(#entries)
  local rows = {}
  local first, last = visible_window(#entries)
  for index = first, last do
    local entry = entries[index]
    rows[#rows + 1] = scene.row_text(entry.title, entry.qualified, index == selected)
  end
  local state = {
    rows = rows,
    query = query,
    matched = stats.matched,
    total = stats.scanned,
    source_ok = source_ok,
    note = note,
  }
  if #entries == 0 and source_ok and query ~= "" then
    state.empty_note = scene.NO_MATCH_NOTE
  end
  return scene.view(state), entries
end

-- The W-01 capture table, or nil on a host that predates it. Checked on every
-- use (never cached) so a mid-generation bridge change cannot wedge the
-- toggle path.
local function overlay_table()
  if bitty.ui == nil then
    return nil
  end
  local overlay = bitty.ui.overlay
  if type(overlay) ~= "table" then
    return nil
  end
  return overlay
end

-- Paint the interactive scene for the current filter state on the held
-- session. Returns false when there is no session or the host rejects the
-- update; in both cases the previous scene (or no scene) stays on screen and
-- the failure never reaches the caller.
local function paint()
  if session == nil then
    return false
  end
  local ui_overlay = overlay_table()
  if ui_overlay == nil or type(ui_overlay.update) ~= "function" then
    return false
  end
  local node = build_scene()
  local ok, updated = pcall(ui_overlay.update, session, node)
  return ok and updated ~= false
end

-- Close the palette: end the capture session (the Core destroys the surface)
-- and report no displayed entries. Release is Core-idempotent and deliberately
-- ungated, so a revoked grant or an already-ended session still clears the
-- local state instead of throwing.
local function close(reason)
  local handle = session
  session = nil
  toggled = false
  note = nil
  selected = 1
  if handle ~= nil then
    local ui_overlay = overlay_table()
    if ui_overlay ~= nil and type(ui_overlay.release) == "function" then
      pcall(ui_overlay.release, handle, reason or "cancelled")
    end
  end
  return 0
end

-- Open the palette: acquire the focusable surface plus capture, then paint
-- the interactive scene. Returns the matched entry list; the toggle caller
-- reports its length. Any acquire or update failure degrades to a
-- command-only open (the count is still returned, no surface appears, and
-- nothing throws).
local function open()
  query = string.gsub(filter.truncate_query(initial_query()), "%c", "")
  selected = 1
  note = nil
  local node, entries = build_scene()
  local ui_overlay = overlay_table()
  if ui_overlay == nil or type(ui_overlay.acquire) ~= "function" then
    return entries
  end
  local ok, handle =
    pcall(ui_overlay.acquire, { title = scene.TITLE, placeholder = scene.PLACEHOLDER })
  if not ok or handle == nil then
    return entries
  end
  session = handle
  local pok, updated = pcall(ui_overlay.update, session, node)
  if (not pok) or updated == false then
    -- The session died between acquire and paint; end it and degrade rather
    -- than holding a blank capture.
    if type(ui_overlay.release) == "function" then
      pcall(ui_overlay.release, session, "cancelled")
    end
    session = nil
  end
  return entries
end

-- Invoke the highlighted command through the host command surface. On success
-- the overlay closes with the `submitted` disposition. On refusal the overlay
-- stays open with a typed row: an empty-args schema rejection is reported as
-- "Needs arguments" (the host validates before the callee runs), and every
-- other refusal carries the host error code.
local function invoke_selected()
  local entries = current_view()
  if #entries == 0 then
    -- The empty/no-match placeholder already explains why there is nothing
    -- to run; do not stack a second typed row on top of it.
    note = nil
    paint()
    return false
  end
  clamp_selection(#entries)
  local entry = entries[selected]
  local commands = bitty.commands
  if type(commands) ~= "table" or type(commands.invoke) ~= "function" then
    note = scene.UNAVAILABLE_INVOKE_NOTE
    paint()
    return false
  end
  local ok, result = pcall(commands.invoke, entry.qualified, {})
  if ok then
    close("submitted")
    return true
  end
  local code = nil
  local message = nil
  if type(result) == "table" then
    code = result.code
    message = result.message
  end
  if code == "E_COMMAND_INVALID" then
    -- Core validates args before the callee runs and reports "args do not
    -- satisfy the command schema"; a result-schema violation is the only
    -- E_COMMAND_INVALID raised after the body ran. Keep the two distinct
    -- without inventing an argument editor (bitty#2965).
    local result_violation =
      type(message) == "string" and string.find(message, "result", 1, true) ~= nil
    if result_violation then
      note = scene.REFUSED_NOTE .. ": " .. code
    else
      note = scene.NEEDS_ARGS_NOTE .. ": " .. entry.title
    end
  elseif type(code) == "string" then
    note = scene.REFUSED_NOTE .. ": " .. code
  else
    note = scene.REFUSED_NOTE
  end
  paint()
  return false
end

local function append_text(text)
  if type(text) ~= "string" or text == "" then
    return
  end
  local cleaned = string.gsub(text, "%c", "")
  if cleaned == "" then
    return
  end
  query = filter.truncate_query(query .. cleaned)
  selected = 1
  note = nil
end

local function backspace()
  if query == "" then
    return
  end
  query = filter.drop_last_char(query)
  selected = 1
  note = nil
end

local function move_selection(delta)
  local entries = current_view()
  local total = #entries
  if total == 0 then
    selected = 1
  else
    selected = selected + delta
    if selected < 1 then
      selected = total
    end
    if selected > total then
      selected = 1
    end
  end
  note = nil
end

-- Classify one captured key event. The flat `text` field carries either the
-- produced text or the host's `key:<Name>` fallback; a modified event also
-- carries `data.key` from the chord channel (issue #2098).
local function key_action(text, data)
  if type(data) == "table" and type(data.key) == "string" then
    local key = data.key
    if key == "up" then
      return "up"
    end
    if key == "down" then
      return "down"
    end
    if key == "enter" then
      return "enter"
    end
    if key == "escape" then
      return "escape"
    end
    if key == "backspace" then
      return "backspace"
    end
    if key == "space" then
      return "space"
    end
    -- A modified character is a chord, never text insertion.
    return "ignore"
  end
  if type(text) ~= "string" or text == "" then
    return "ignore"
  end
  if text == "\r" or text == "\n" then
    return "enter"
  end
  if text == "\27" then
    return "escape"
  end
  if text == "\127" or text == "\8" then
    return "backspace"
  end
  local named = string.match(text, "^key:(.+)$")
  local bare_named = text == "ArrowUp"
    or text == "ArrowDown"
    or text == "Enter"
    or text == "Escape"
    or text == "Backspace"
    or text == "Space"
  if named == nil and bare_named then
    -- Tolerate a caller that forwards the bare key name instead of the
    -- host's `key:<Name>` fallback.
    named = text
  end
  if named ~= nil then
    if named == "ArrowUp" or named == "up" or named == "Up" then
      return "up"
    end
    if named == "ArrowDown" or named == "down" or named == "Down" then
      return "down"
    end
    if named == "Enter" or named == "enter" then
      return "enter"
    end
    if named == "Escape" or named == "escape" or named == "Esc" then
      return "escape"
    end
    if named == "Backspace" or named == "backspace" then
      return "backspace"
    end
    if named == "Space" or named == "space" then
      return "space"
    end
    return "ignore"
  end
  return "text"
end

-- Apply one drained input event. Returns true when the event ended the
-- session, so the drain loop stops delivering further queued input.
local function handle_event(event)
  if type(event) ~= "table" then
    return false
  end
  local kind = event.type
  if kind == "text" then
    append_text(event.text)
    paint()
    return false
  end
  if kind ~= "key" then
    return false
  end
  local action = key_action(event.text, event.data)
  if action == "text" then
    local text = event.text
    -- j/k are navigation while the query is empty; once filtering starts
    -- they are ordinary text so a query can still contain them.
    if query == "" and (text == "j" or text == "k") then
      move_selection(text == "j" and 1 or -1)
      paint()
      return false
    end
    append_text(text)
    paint()
    return false
  end
  if action == "space" then
    append_text(" ")
    paint()
    return false
  end
  if action == "up" then
    move_selection(-1)
    paint()
    return false
  end
  if action == "down" then
    move_selection(1)
    paint()
    return false
  end
  if action == "backspace" then
    backspace()
    paint()
    return false
  end
  if action == "enter" then
    return invoke_selected()
  end
  if action == "escape" then
    close("cancelled")
    return true
  end
  return false
end

-- Drain the capture queue through the owner-initiated poll. A released or
-- stale session clears the local state; a host without poll leaves the last
-- scene in place instead of throwing.
local function drain()
  if session == nil then
    return
  end
  local ui_overlay = overlay_table()
  if ui_overlay == nil or type(ui_overlay.poll) ~= "function" then
    return
  end
  local ok, result = pcall(ui_overlay.poll, session)
  if not ok or type(result) ~= "table" then
    -- A stale or unusable session must not keep the host capture alive with
    -- no UI; release is idempotent and ungated.
    close("cancelled")
    return
  end
  if result.status == "released" then
    toggled = false
    session = nil
    note = nil
    return
  end
  local events = result.events
  if type(events) ~= "table" then
    return
  end
  for _, event in ipairs(events) do
    if session == nil then
      return
    end
    if handle_event(event) then
      return
    end
  end
end

bitty.commands.register({
  id = "toggle",
  title = "Palette: toggle",
  description = "Toggle the command palette overlay and show the filtered entry list.",
  args_schema = { type = "object", properties = {}, additionalProperties = false },
  result_schema = { type = "integer", minimum = 0, maximum = filter.MAX_ENTRIES },
  run = function(_args)
    toggled = not toggled
    if not toggled then
      return close()
    end
    return #open()
  end,
})

-- Refresh the presented list when focus moves while the palette is open.
bitty.events.subscribe("focus.changed", function(_event)
  if toggled and session ~= nil then
    paint()
  end
end)

-- Reset the toggle state when the capture session ends without our asking
-- (focus switch, idle timeout, unload): the surface is already gone, so the
-- next toggle re-opens instead of closing nothing. The single-capture
-- invariant makes an unconditional reset safe: no foreign session can be
-- active while ours is, a foreign end while we are closed is a no-op on
-- already-false state, and our own voluntary close observes this event after
-- the release above idempotently.
bitty.events.subscribe("overlay.released", function(_event)
  toggled = false
  session = nil
  note = nil
end)

-- Cold-path input nudge: the host publishes this observation while the
-- capture owner has undrained queued input. Polling is owner-initiated, so no
-- plugin callback ever runs on the input hot path.
bitty.events.subscribe("overlay.input.available", function(_event)
  if session ~= nil then
    drain()
  end
end)

return M
