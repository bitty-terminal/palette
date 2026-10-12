-- Minimal in-process `bitty` host stub for the palette behavior tests.
--
-- This is a test double, not a host implementation: it models only the
-- accepted surface the palette uses — Plugin API v1 (ADR 0009 / Plugin API v1
-- Lua Surface RFC: commands, events, settings, `bitty.ui.mount`/`update`
-- scene validation) plus the accepted W-01 focusable-overlay capture surface
-- (`bitty.ui.overlay.acquire` in spec form / `update` / `release` on the
-- session block, gated by `ui.overlay.focus`; `overlay.released` observation
-- event) — with fail-closed capability gates, manifest-declared command/event
-- validation, and the v1 declarative scene validation (`Text`, `Row`,
-- `Column`, `List` only, depth `16`). It performs no I/O, spawns nothing,
-- and never touches the network or the filesystem.

local MockHost = {}
MockHost.__index = MockHost

local UI_SLOTS = {
  terminal = true,
  top = true,
  bottom = true,
  left = true,
  right = true,
  tabline = true,
  statusline = true,
  overlay = true,
}

local UI_V1_NODE_KINDS = {
  Text = true,
  Row = true,
  Column = true,
  List = true,
}

local UI_V1_EXCLUDED_NODE_KINDS = {
  Block = true,
  Image = true,
  CodeBlock = true,
  Table = true,
  Rule = true,
}

local UI_MAX_DEPTH = 16

local function fail(class, code, message)
  error({ class = class, code = code, message = message }, 0)
end

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, child in pairs(value) do
    copy[key] = deepcopy(child)
  end
  return copy
end

local function validate_component(component, depth)
  if depth > UI_MAX_DEPTH then
    fail("validation", "E_UI_COMPONENT_INVALID", "component depth exceeds 16")
  end
  if type(component) ~= "table" then
    fail("validation", "E_UI_COMPONENT_INVALID", "component must be a table")
  end
  local kind = component.kind
  if type(kind) ~= "string" then
    fail("validation", "E_UI_COMPONENT_INVALID", "component.kind must be a string")
  end
  if UI_V1_EXCLUDED_NODE_KINDS[kind] then
    fail("validation", "E_UI_COMPONENT_INVALID", "node kind " .. kind .. " is excluded from Plugin API v1")
  end
  if not UI_V1_NODE_KINDS[kind] then
    fail("validation", "E_UI_COMPONENT_INVALID", "unknown node kind " .. kind)
  end
  if kind == "Text" then
    if type(component.text) ~= "string" then
      fail("validation", "E_UI_COMPONENT_INVALID", "Text components require a string text field")
    end
    return
  end
  if type(component.children) ~= "table" then
    fail("validation", "E_UI_COMPONENT_INVALID", kind .. " components require a children array")
  end
  for _, child in ipairs(component.children) do
    validate_component(child, depth + 1)
  end
end

function MockHost.new(options)
  options = options or {}
  local self = setmetatable({}, MockHost)
  self.plugin_id = options.plugin_id or "bitty-terminal.palette"
  self.grants = {}
  for _, name in ipairs(options.grants or {}) do
    self.grants[name] = true
  end
  self.declared_commands = {}
  for _, name in ipairs(options.commands or {}) do
    self.declared_commands[name] = true
  end
  self.declared_events = {}
  for _, name in ipairs(options.events or {}) do
    self.declared_events[name] = true
  end
  self.settings = options.settings or {}
  self.commands = {}
  self.subscriptions = {}
  self.blocks = {}
  self.updates = 0
  -- Transient input-capture owner while a session is active:
  -- `{ handle = <overlay block> }`, or nil when idle. Single-owner switch
  -- mirroring the Core `OverlayCapture` acquire/release contract.
  self.capture = nil
  self.handle_counter = 0
  self.sequence = 1
  self.bitty = self:build_bitty()
  return self
end

function MockHost:grant(name)
  self.grants[name] = true
end

function MockHost:next_handle()
  self.handle_counter = self.handle_counter + 1
  return self.handle_counter
end

function MockHost:assert_capability(surface, capability)
  if not self.grants[capability] then
    fail("runtime", "E_CAPABILITY_DENIED", surface .. " requires capability " .. capability)
  end
end

function MockHost:build_bitty()
  local self = self
  return {
    api_version = "1.0.0",
    commands = {
      register = function(def)
        if type(def) ~= "table" or type(def.id) ~= "string" then
          fail("validation", "E_DEF_INVALID", "command definition is invalid")
        end
        if def.title == nil or def.title == "" or type(def.run) ~= "function" then
          fail("validation", "E_DEF_INVALID", "command requires title and run")
        end
        local qualified = self.plugin_id .. ":" .. def.id
        if not self.declared_commands[qualified] then
          fail("validation", "E_COMMAND_UNDECLARED", "command is not reserved in the manifest: " .. qualified)
        end
        if self.commands[qualified] ~= nil then
          fail("validation", "E_COMMAND_DUPLICATE", "duplicate command: " .. qualified)
        end
        self.commands[qualified] = def
        return self:next_handle()
      end,
    },
    events = {
      subscribe = function(name, handler)
        if type(name) ~= "string" or type(handler) ~= "function" then
          fail("validation", "E_DEF_INVALID", "event subscription is invalid")
        end
        if not self.declared_events[name] then
          fail("validation", "E_EVENT_UNDECLARED", "event is not declared in the manifest: " .. name)
        end
        self.subscriptions[#self.subscriptions + 1] = { kind = name, handler = handler }
        return self:next_handle()
      end,
    },
    settings = {
      get = function(key)
        if type(key) ~= "string" then
          fail("validation", "E_SETTINGS_KEY_INVALID", "settings key must be a string")
        end
        return self.settings[key]
      end,
    },
    ui = {
      mount = function(slot, component)
        self:assert_capability("bitty.ui.mount", "ui.rich")
        if slot == "overlay" then
          self:assert_capability("bitty.ui.mount:overlay", "ui.overlay")
        end
        if type(slot) ~= "string" or not UI_SLOTS[slot] then
          fail("validation", "E_UI_COMPONENT_INVALID", "unknown slot")
        end
        validate_component(component, 1)
        local handle = self:next_handle()
        self.blocks[handle] =
          { generation = 1, version = 1, slot = slot, component = deepcopy(component) }
        return handle
      end,
      update = function(handle, component)
        self:assert_capability("bitty.ui.update", "ui.rich")
        validate_component(component, 1)
        local block = self.blocks[handle]
        if block == nil then
          return false
        end
        block.version = block.version + 1
        block.component = deepcopy(component)
        self.updates = self.updates + 1
        return true
      end,
      -- Accepted W-01 capture surface (spec form). Acquire mounts the
      -- session surface and starts capture in one switch, gated by the
      -- single coupled `ui.overlay.focus` grant; release destroys the
      -- session surface and is ungated so cleanup can never wedge input.
      overlay = {
        acquire = function(spec)
          self:assert_capability("bitty.ui.overlay.acquire", "ui.overlay.focus")
          local title, placeholder = "", ""
          if spec ~= nil then
            if type(spec) ~= "table" then
              fail(
                "validation",
                "E_UI_COMPONENT_INVALID",
                "ui.overlay.acquire spec must be a table"
              )
            end
            if spec.title ~= nil then
              if type(spec.title) ~= "string" then
                fail(
                  "validation",
                  "E_UI_COMPONENT_INVALID",
                  "ui.overlay.acquire spec fields must be strings"
                )
              end
              title = spec.title
            end
            if spec.placeholder ~= nil then
              if type(spec.placeholder) ~= "string" then
                fail(
                  "validation",
                  "E_UI_COMPONENT_INVALID",
                  "ui.overlay.acquire spec fields must be strings"
                )
              end
              placeholder = spec.placeholder
            end
          end
          if self.capture ~= nil then
            fail(
              "runtime",
              "E_UI_ALREADY_CAPTURED",
              "a focusable-overlay input capture is already active"
            )
          end
          local children = {}
          if title ~= "" then
            children[#children + 1] = { kind = "Text", text = title }
          end
          if placeholder ~= "" then
            children[#children + 1] = { kind = "Text", text = placeholder }
          end
          if #children == 0 then
            children[1] = { kind = "Text", text = "" }
          end
          local component = { kind = "Column", children = children }
          validate_component(component, 1)
          local handle = self:next_handle()
          self.blocks[handle] =
            { generation = 1, version = 1, slot = "overlay", component = deepcopy(component) }
          self.capture = { handle = handle }
          return handle
        end,
        update = function(handle, component)
          self:assert_capability("bitty.ui.overlay.update", "ui.overlay.focus")
          if self.capture == nil or self.capture.handle ~= handle then
            fail(
              "runtime",
              "E_UI_NOT_OWNER",
              "no focusable-overlay input capture is held for this handle"
            )
          end
          validate_component(component, 1)
          local block = self.blocks[handle]
          if block == nil then
            return false
          end
          block.version = block.version + 1
          block.component = deepcopy(component)
          self.updates = self.updates + 1
          return true
        end,
        release = function(handle, reason)
          if reason ~= nil and reason ~= "submitted" and reason ~= "cancelled" then
            fail(
              "validation",
              "E_DEF_INVALID",
              "ui.overlay.release reason must be 'submitted' or 'cancelled'"
            )
          end
          if self.capture ~= nil and self.capture.handle == handle then
            self.capture = nil
            self.blocks[handle] = nil
            return true
          end
          return false
        end,
      },
    },
  }
end

function MockHost:publish(kind, payload)
  local delivered = 0
  for _, subscription in ipairs(self.subscriptions) do
    if subscription.kind == kind then
      delivered = delivered + 1
      subscription.handler({
        kind = kind,
        sequence = self.sequence,
        payload = deepcopy(payload or {}),
      })
      self.sequence = self.sequence + 1
    end
  end
  return delivered
end

function MockHost:run(command_id, args)
  local qualified = self.plugin_id .. ":" .. command_id
  local def = self.commands[qualified]
  if def == nil then
    fail("validation", "E_COMMAND_UNDECLARED", "command is not registered: " .. qualified)
  end
  return def.run(args or {})
end

-- Drop the capture owner and destroy the session surface without notifying
-- the plugin, simulating a Core-side involuntary session end (focus switch,
-- timeout, unload). Tests then deliver the `overlay.released` observation
-- with `publish`.
function MockHost:revoke_overlay()
  if self.capture ~= nil then
    self.blocks[self.capture.handle] = nil
    self.capture = nil
  end
end

-- The session block of the live capture owner (the block the Core would
-- surface), or nil when no session holds capture.
function MockHost:session_block()
  if self.capture == nil then
    return nil
  end
  return self.blocks[self.capture.handle]
end

return MockHost
