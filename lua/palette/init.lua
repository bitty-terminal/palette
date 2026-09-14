-- Entry point for Bitty Palette (bitty-terminal.palette).
--
-- The host evaluates this file once per plugin activation and owns every
-- resource created here for the lifetime of that generation. Registration
-- calls (`bitty.commands.register`, `bitty.events.subscribe`,
-- `bitty.ui.mount`) are valid only while this file executes.
--
-- Accepted surface: Plugin API v1 Lua Surface RFC (ADR 0009). Capabilities
-- requested in `bitty-plugin.toml` are `ui.rich` (declarative UI mount) and
-- `ui.overlay` (the overlay slot). The bundled Rust realization declared only
-- `ui.overlay` because it used the lower-level Panel Runtime overlay path; the
-- accepted Lua overlay path (`bitty.ui.mount`) additionally requires
-- `ui.rich`, so this independent package declares both. This is a recorded,
-- intentional difference from the bundled manifest.
--
-- v1 data adapter: the accepted surface exposes no command-registry
-- enumeration and no `PickerProvider` (the Plugin Reuse and Provider Ecology
-- RFC is draft/post-1.0), so the palette reads its bounded entry list and
-- query from its own settings namespace (`entries`, `query`). Host overlay
-- support (`bitty.ui.mount`/`update`) is not yet in the `bitty` Lua bridge;
-- the plugin degrades to command-only mode until it lands. See the README
-- "Known gaps" section.

local filter = require("palette.filter")
local scene = require("palette.scene")

local M = {}

local toggled = false

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

-- The overlay block is mounted once during activation because `ui.mount` is a
-- registration-time call. Toggling and focus changes update it. When the host
-- bridge does not yet expose `bitty.ui`, the plugin runs in command-only mode.
local overlay = nil
if bitty.ui ~= nil and type(bitty.ui.mount) == "function" then
  overlay = bitty.ui.mount("overlay", scene.empty())
end

local function refresh()
  local filtered = filter.filter(entries(), query())
  if overlay ~= nil then
    bitty.ui.update(overlay, scene.list(filtered))
  end
  return filtered
end

bitty.commands.register({
  id = "toggle",
  title = "Palette: toggle",
  description = "Toggle the command palette overlay and show the filtered entry list.",
  run = function(_args)
    toggled = not toggled
    local filtered = refresh()
    if not toggled and overlay ~= nil then
      bitty.ui.update(overlay, scene.empty())
    end
    return #filtered
  end,
})

-- Refresh the presented list when focus moves while the palette is open.
bitty.events.subscribe("focus.changed", function(_event)
  if toggled then
    refresh()
  end
end)

return M
