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
--
-- Every host UI call is guarded: mount denial or scene-validation failure at
-- activation leaves the palette in command-only mode instead of crashing the
-- generation, and a rejected update keeps the last successfully presented
-- scene instead of propagating to the command caller or event dispatcher.

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
-- registration-time call. Mounting is capability-gated and validates the
-- scene, so the call is guarded: a failure leaves the palette in command-only
-- mode instead of crashing activation. When the host bridge does not yet
-- expose `bitty.ui`, the plugin also runs in command-only mode.
local overlay = nil
if bitty.ui ~= nil and type(bitty.ui.mount) == "function" then
  local ok, handle = pcall(bitty.ui.mount, "overlay", scene.empty())
  if ok and handle ~= nil then
    overlay = handle
  end
end

-- Present `node` in the overlay. Returns false when no block is mounted or the
-- host rejects the update; in both cases the previous scene (or no scene)
-- stays on screen and the failure never reaches the caller.
local function render(node)
  if overlay == nil then
    return false
  end
  local ok, updated = pcall(bitty.ui.update, overlay, node)
  return ok and updated ~= false
end

local function refresh()
  local filtered = filter.filter(entries(), query())
  render(scene.list(filtered))
  return filtered
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
      -- Closing presents the empty scene in a single render; the filtered
      -- list is not recomputed because nothing is displayed.
      render(scene.empty())
      return 0
    end
    return #refresh()
  end,
})

-- Refresh the presented list when focus moves while the palette is open.
bitty.events.subscribe("focus.changed", function(_event)
  if toggled then
    refresh()
  end
end)

return M
