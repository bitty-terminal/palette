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
-- default scene (title plus filtered items or the placeholder row) with the
-- session-owned update, and destroys the surface on release. The Core surfaces
-- only the capture owner's block, so the acquire is what makes the overlay
-- visible; without it the toggle degrades to command-only counts.
--
-- v1 data adapter: the accepted surface exposes no command-registry
-- enumeration and no `PickerProvider` (the Plugin Reuse and Provider Ecology
-- RFC is draft/post-1.0), so the palette reads its bounded entry list and
-- query from its own settings namespace (`entries`, `query`). Captured
-- keystrokes are not drained: v1 has no text-input surface for overlays, so
-- live query typing stays a follow-up and the query is read from settings
-- rather than typed live. See the README "Known gaps" section.
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

local function setting(name)
  local ok, value = pcall(bitty.settings.get, name)
  if ok then
    return value
  end
  return nil
end

local function entries()
  local value = setting("entries")
  if type(value) == "table" then
    return value
  end
  return {}
end

local function query()
  local value = setting("query")
  if type(value) == "string" then
    return value
  end
  return ""
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

-- Paint the default scene for the current filter state on the held session.
-- Returns false when there is no session or the host rejects the update; in
-- both cases the previous scene (or no scene) stays on screen and the failure
-- never reaches the caller.
local function paint()
  if session == nil then
    return false
  end
  local ui_overlay = overlay_table()
  if ui_overlay == nil or type(ui_overlay.update) ~= "function" then
    return false
  end
  local filtered = filter.filter(entries(), query())
  local ok, updated = pcall(ui_overlay.update, session, scene.default(filtered))
  return ok and updated ~= false
end

-- Open the palette: acquire the focusable surface plus capture, then paint
-- title/placeholder/items. Returns the filtered entry list; the toggle caller
-- reports its length. Any acquire or update failure degrades to a
-- command-only open (the count is still returned, no surface appears, and
-- nothing throws).
local function open()
  local filtered = filter.filter(entries(), query())
  local ui_overlay = overlay_table()
  if ui_overlay == nil or type(ui_overlay.acquire) ~= "function" then
    return filtered
  end
  local ok, handle =
    pcall(ui_overlay.acquire, { title = scene.TITLE, placeholder = scene.PLACEHOLDER })
  if not ok or handle == nil then
    return filtered
  end
  session = handle
  local pok, updated = pcall(ui_overlay.update, session, scene.default(filtered))
  if (not pok) or updated == false then
    -- The session died between acquire and paint; end it and degrade rather
    -- than holding a blank capture.
    if type(ui_overlay.release) == "function" then
      pcall(ui_overlay.release, session, "cancelled")
    end
    session = nil
  end
  return filtered
end

-- Close the palette: end the capture session (the Core destroys the surface)
-- and report no displayed entries. Release is Core-idempotent and deliberately
-- ungated, so a revoked grant or an already-ended session still clears the
-- local state instead of throwing.
local function close()
  local handle = session
  session = nil
  if handle ~= nil then
    local ui_overlay = overlay_table()
    if ui_overlay ~= nil and type(ui_overlay.release) == "function" then
      pcall(ui_overlay.release, handle, "cancelled")
    end
  end
  return 0
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
end)

return M
