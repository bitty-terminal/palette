# Bitty Palette

Command palette and picker UI for the [Bitty terminal](https://github.com/bitty-terminal/bitty),
presented through the overlay slot with declarative list and text primitives
only.

- Plugin id: `bitty-terminal.palette`
- Lua module: `lua/palette/`
- Capabilities: `ui.overlay.focus`
- Lazy commands: `bitty-terminal.palette:toggle`
- Lazy events: `focus.changed`, `overlay.released`

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

| Path                     | Purpose                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------ |
| `bitty-plugin.toml`      | Static manifest: identity, compatibility, capability requests, and lazy triggers.                |
| `lua/palette/init.lua`   | Entry point evaluated once per activation; registers the toggle command and the capture session. |
| `lua/palette/filter.lua` | Bounded, host-free input scanning, filtering, and text-truncation policy.                        |
| `lua/palette/scene.lua`  | Declarative `List`/`Text` overlay composition, including the non-empty default scene.            |
| `tests/`                 | Lua 5.4 behavior suite and LuaLS conformance.                                                    |
| `package.json`           | Pinned dev dependencies: the authoritative `bitty-plugin-lint` by commit, plus tooling.          |
| `bun.lock`               | Locked dependency graph installed by `just install`.                                             |
| `justfile`               | Quality gates with pinned tool versions.                                                         |

## Behavior

The plugin keeps the behavior and bounds of the former bundled palette; this
package now defines them:

- case-insensitive substring filtering over the active host command catalog
  (`bitty.commands.list`, bounded by the host), at most `128` displayed
  entries (`PALETTE_MAX_ENTRIES`);
- candidate input bounded to `1024` examined catalog rows per filter pass
  (`MAX_INPUT`); larger catalogs are cut at the bound and the cut is reported
  through the filter stats (`filter.filter` returns `{ scanned, truncated }` as
  its second value);
- a catalog the host cannot serve paints `Command list unavailable`, so a
  broken source is never mistaken for an empty one;
- the declared `query` setting (default `""`) narrows the catalog; it is read
  through `bitty.settings.get` and fails closed to the empty query;
- query truncated to `128` characters, display text truncated to the host
  overlay text bound `128` (`MAX_OVERLAY_TEXT_LEN`) at a UTF-8 code-point
  boundary;
- overlay content composed as a single declarative `List` of `Text` rows
  (`Text`, `Row`, `Column`, `List` are the only Plugin API v1 node kinds);
- every open acquires the focusable overlay plus transient input capture in
  one Core-owned switch
  (`bitty.ui.overlay.acquire({ title = "Palette", placeholder = "Filter commands" })`);
  the Core surfaces only the capture owner's block, so the acquire is what
  makes the overlay visible;
- the open scene is never empty: the title row plus the filtered command rows,
  or the title plus a `No entries` placeholder row when the catalog is empty,
  or `Command list unavailable` when the host cannot serve the catalog — a real
  UI, not a bare pill;
- closing ends the session (`bitty.ui.overlay.release(handle, "cancelled")`),
  which destroys the surface; an involuntary session end (focus switch, idle
  timeout, unload) observed through `overlay.released` resets the toggle state
  so the next toggle re-opens;
- host capture calls are `pcall`-guarded: a denied focus grant, a live foreign
  session, or a host without the capture table degrades to command-only mode
  (counts still returned), and a rejected session update keeps the last
  successfully presented scene instead of throwing at the command caller or
  the event dispatchers;
- `toggle` returns the number of displayed entries (`0` when closing) and
  declares a closed empty-object `args_schema` plus an integer `result_schema`
  matching the returned count;
- refresh on `focus.changed` while a session is held.

## Capability difference from the former bundled realization

This package is now the only realization of the palette envelope and
behavior. The historical bundled Rust realization in `bitty` is gone: its
manifest left the bundled catalog (`crates/bitty-plugin-host/src/bundled.rs`)
when the palette migrated to this package (`CTX-0397`), and its runtime module
(`crates/bitty-runtime/src/palette.rs`) was removed by `bitty` PR #1611
(commit `67cdcc14`). That realization declared only `ui.overlay` because it
used the lower-level Panel Runtime overlay path.

This package requests neither v1 presentation grant. The accepted W-01
overlay-input-capture contract couples the focusable surface and its capture
session under the single `ui.overlay.focus` grant, and the spec-acquire path
mounts the surface without passing the v1 `ui.overlay` slot gate — so the
former `ui.rich` + `ui.overlay` pair is unrequested. The v1 `ui.overlay` slot
stays presentation-only and non-focusable by design.

This is a recorded, intentional difference for `bitty-terminal/bitty#1971`.
Dropping the v1 grants is a narrowing (one grant instead of two) with no new
authority: no filesystem, process, network, clipboard, or Terminal Truth
access, and release stays ungated so cleanup can never wedge input.

## Known gaps

- **Interactive query input.** v1 has no text-input surface for overlays, and
  this package does not yet drain the capture queue (`bitty.ui.overlay.poll`),
  so the query is read from the declared `query` setting rather than typed live.
  A picker-provider API is still draft/post-1.0; the host command catalog is the
  entry source.

## Development

Install the pinned dependencies once, then run the same gate CI runs:

```sh
just install   # bun install --frozen-lockfile; the only network step
just check
```

`just install` materializes `bitty-plugin-lint` (bitty-plugin-sdk, pinned by
commit in `package.json` and `bun.lock`) and `luaparse`; every gate then runs
offline and fails closed when the dependency is absent. `just manifest`
validates `bitty-plugin.toml` with the authoritative SDK linter against the
accepted contract in bitty-docs
`docs/specifications/plugin-platform-rfc.md` (file name, identity,
compatibility, capability closed set, lazy triggers, hard limits). `just lua`
parses the Lua modules with the pinned `luaparse` 0.3.1 grammar. `lua5.4` is
required for the behavior suite; `lua-language-server` is optional and
`just test-luals` skips with exit 0 when absent.

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

Only `ui.overlay.focus` is requested: one focusable overlay plus the bounded
transient input-capture session for one interaction. The plugin has no
filesystem, process, network, clipboard, terminal-input, or persistent-state
authority. It performs no I/O and spawns nothing. Report vulnerabilities through the process
in the umbrella project's security policy rather than a public issue.
