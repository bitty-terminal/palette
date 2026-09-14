# Bitty Palette

Command palette and picker UI for the [Bitty terminal](https://github.com/bitty-terminal/bitty),
presented through the overlay slot with declarative list and text primitives
only.

- Plugin id: `bitty-terminal.palette`
- Lua module: `lua/palette/`
- Capabilities: `ui.rich`, `ui.overlay`
- Lazy commands: `bitty-terminal.palette:toggle`
- Lazy events: `focus.changed`

This repository is the independent first-party package created by the bundled
plugin split decision (OQ-053, `bitty-plugins-docs` `product/bundled-plugin-split-decision.md`),
owned by `bitty` `CTX-0397`. It was scaffolded from
[bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template).

## Status

Pre-implementation ecosystem: the plugin package, manifest, and policy are
implemented and tested headlessly; the Bitty host is still landing the Plugin
API v1 overlay bridge. Nothing here is a compatibility promise beyond the
manifest `[compat]` ranges.

## Layout

| Path                            | Purpose                                                                                         |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `bitty-plugin.toml`             | Static manifest: identity, compatibility, capability requests, and lazy triggers.               |
| `lua/palette/init.lua`          | Entry point evaluated once per activation; registers the toggle command and mounts the overlay. |
| `lua/palette/filter.lua`        | Bounded, host-free filtering and text-truncation policy.                                        |
| `lua/palette/scene.lua`         | Declarative `List`/`Text` overlay composition.                                                  |
| `tests/`                        | Lua 5.4 behavior suite, LuaLS conformance, and the SDK manifest-lint wrapper.                   |
| `scripts/validate-manifest.mjs` | Transitional manifest check; `bitty-plugin-lint` (R-SDK-2) is authoritative.                    |
| `justfile`                      | Quality gates with pinned tool versions.                                                        |

## Behavior

The plugin keeps the bundled palette behavior and bounds:

- case-insensitive substring filtering over a bounded entry list, at most
  `128` displayed entries (`PALETTE_MAX_ENTRIES`);
- query truncated to `128` characters, display text truncated to the host
  overlay text bound `128` (`MAX_OVERLAY_TEXT_LEN`) at a UTF-8 code-point
  boundary;
- overlay content composed as a single declarative `List` of `Text` rows
  (`Text`, `Row`, `Column`, `List` are the only Plugin API v1 node kinds);
- refresh on `focus.changed` while the palette is open.

## Capability difference from the bundled realization

The bundled Rust realization (`bitty` `crates/bitty-plugin-host/src/bundled.rs`
`palette_manifest`, `crates/bitty-runtime/src/palette.rs`) declared only
`ui.overlay` because it used the lower-level Panel Runtime overlay path. The
accepted Plugin API v1 Lua overlay path (`bitty.ui.mount` on the `overlay`
slot) requires **both** `ui.rich` and `ui.overlay` per ADR 0009 and the Plugin
API v1 Lua Surface RFC. This package therefore requests `ui.rich` as well.

This is a recorded, intentional difference. Reconciling the bundled manifest or
introducing a `ui.overlay`-only plain-overlay Lua path is tracked as a
follow-up; see "Known gaps".

## Known gaps

- **Host overlay bridge.** The current `bitty` Lua bridge
  (`crates/bitty-lua/src/host.rs`) implements commands, events, settings,
  store, terminal snapshots, notifications, and timers, but not
  `bitty.ui.mount`/`bitty.ui.update`. The plugin activates in command-only mode
  and returns the filtered entry count until that surface lands. Tracked as a
  follow-up task in `bitty`.
- **Entry source.** The accepted v1 surface exposes no command-registry
  enumeration and no `PickerProvider` (the Plugin Reuse and Provider Ecology
  RFC is draft/post-1.0). The palette reads its bounded entry list and query
  from its own settings namespace (`entries`, `query`) as a v1 adapter.
- **Interactive query input.** v1 has no text-input surface for overlays, so
  the query is read from settings rather than typed live.

## Development

Run the same gate CI runs:

```sh
bun install --frozen-lockfile
just check
```

`just check` runs Markdown lint, Prettier format check, the transitional
manifest validator, the pinned Lua parser, and the Lua/LuaLS/SDK-manifest test
suites. `lua5.4` is required for the behavior suite; `lua-language-server` and
`bitty-plugin-lint` are optional and their checks skip with exit 0 when absent.

## Install

An external package is installed from a local checkout with the Bitty CLI:

```sh
bitty plugin install /path/to/palette
```

The registry entry in
[bitty-plugins](https://github.com/bitty-terminal/bitty-plugins) points at this
repository; this plugin previously shipped as a bundled (staged, disabled by
default) `bitty-terminal.palette`.

## Security

Only `ui.rich` and `ui.overlay` are requested. The plugin has no filesystem,
process, network, clipboard, terminal-input, or persistent-state authority. It
performs no I/O and spawns nothing. Report vulnerabilities through the process
in the umbrella project's security policy rather than a public issue.
