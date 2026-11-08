# Bitty Palette

Command palette and picker UI for the [Bitty terminal](https://github.com/bitty-terminal/bitty),
presented through the overlay slot with declarative list and text primitives
only.

- Plugin id: `bitty-terminal.palette`
- Lua module: `lua/palette/`
- Capabilities: `ui.overlay.focus`
- Lazy commands: `bitty-terminal.palette:toggle`
- Lazy events: `focus.changed`, `overlay.released`, `overlay.input.available`

This repository is the independent first-party package created by the bundled
plugin split decision (OQ-053, `bitty-plugins-docs` `product/bundled-plugin-split-decision.md`),
owned by `bitty` `CTX-0397`. It was scaffolded from
[bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template).

## Overview

Palette opens a focusable overlay listing the command catalog the host
publishes. Typing narrows the list with a case-insensitive substring match over
the command id, title, and owning plugin id; Up/Down (and `j`/`k`) move the
highlight, and Enter runs the highlighted command through the host-mediated
`bitty.commands.invoke` surface. The overlay closes on success and stays open
with a typed row when the host refuses the invocation (including a command that
needs arguments). The overlay is also released when toggled closed or when
input capture ends. If the host cannot serve the catalog, the overlay says so
instead of showing an empty list.

Open it with `bitty-terminal.palette:toggle`; the plugin installs no default
chord. For example, bind the command to `ctrl+p` as shown under
[Keybindings](#keybindings), press it, type a fragment of a command title (for
example `dash` when Dashboard is installed) to filter the catalog, and press
`Enter`: the highlighted command runs through the host and the overlay closes.
If the highlighted command needs arguments, the overlay stays open with
`Needs arguments: <title>`.

## Install

Prerequisites:

- Bitty `>=0.0.24` with Plugin API `^1.0` (the manifest `[compat]` minimum;
  no upper bound is declared).
- A host that exposes the W-01 overlay capture surface
  (`bitty.ui.overlay.acquire` / `update` / `poll` / `release`), the
  observation-only `overlay.input.available` event, the command catalog
  (`bitty.commands.list`), and host-mediated invocation
  (`bitty.commands.invoke`). Without capture the plugin still runs, but the
  overlay cannot appear; without invocation the overlay lists commands and
  reports `Invocation unavailable` when Enter is pressed.
- Consent to `ui.overlay.focus`, the single coupled grant for the focusable
  overlay and its transient input-capture session.

Install from a local checkout:

```sh
git clone https://github.com/bitty-terminal/palette.git
cd palette
bitty plugin install "$PWD"
bitty plugin enable bitty-terminal.palette
bitty plugin list
```

`bitty plugin install <path>` stages the package under the XDG data store and
records the capability you consent to; it executes no plugin code (`--yes`
approves non-interactively). Verify activation with `bitty plugin list`: the
entry must show `bitty-terminal.palette`, version `0.0.1`, source
`local-path`, enabled, and the `ui.overlay.focus` grant.
`bitty plugin info bitty-terminal.palette` prints the recorded grant set.

## Commands

| Command                         | What it does                                                                              | Arguments | Default keybinding |
| ------------------------------- | ----------------------------------------------------------------------------------------- | --------- | ------------------ |
| `bitty-terminal.palette:toggle` | Opens the palette and returns the number of displayed rows, or closes it and returns `0`. | None      | None               |

The command declares a closed empty-object argument schema and returns an
integer between `0` and `128`. Refreshing while open repaints the filtered
catalog; a denied capture grant or a live foreign capture session degrades to
command-only behavior, where the count is still returned but no overlay is
shown. The palette never dispatches commands itself: Enter calls
`bitty.commands.invoke(qualified, {})`, so the host keeps its deny-by-default
checks, argument validation, and cross-VM containment.

## Configuration

Settings live in `$XDG_CONFIG_HOME/bitty/plugins/bitty-terminal.palette.lua`.
Values are read at activation and pinned to that plugin generation.

| Key     | Type     | Default | Description                                                                                                         | Reload         |
| ------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------- | -------------- |
| `query` | `string` | `""`    | Initial case-insensitive substring filter applied when the overlay opens. Live typing replaces it for that session. | Restart (seed) |

Example:

```lua
-- $XDG_CONFIG_HOME/bitty/plugins/bitty-terminal.palette.lua
return {
  query = "",
}
```

`Restart (seed)` means settings are resolved during activation: there is no
settings watcher or hot-reload path, so edit the file and restart Bitty. The
setting seeds the filter each time the overlay opens; typing while the overlay
is focused replaces that seed for the session, and closing the overlay discards
the live query.

## Keybindings

Palette registers no default keybinding. Bind a chord in
`$XDG_CONFIG_HOME/bitty/init.lua`:

```lua
return {
  keymaps = {
    {
      chord = "ctrl+p",
      action = "command:bitty-terminal.palette:toggle",
      context = "global",
    },
  },
}
```

User keymaps own the binding: a user entry with the same `context + chord`
replaces a shipped entry, and the plugin never binds a chord on its own.

## Troubleshooting

| Code                    | Class        | Cause                                                                                                                    | Remedy                                                                                                                                                                                               |
| ----------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `E_SETTINGS_UNDECLARED` | `validation` | A settings read named a key absent from the manifest `[settings]` declarations.                                          | Install a plugin version whose declarations match the running build. Only `query` is declared; other config entries are ignored.                                                                     |
| `E_INCOMPATIBLE`        | `validation` | The running host does not satisfy `>=0.0.24`, or Plugin API is not `^1.0`.                                               | Upgrade Bitty or install a Palette release whose `[compat]` minimum covers your host.                                                                                                                |
| `E_CAPABILITY_DENIED`   | `runtime`    | The `ui.overlay.focus` grant is missing, expired, or revoked.                                                            | Re-run `bitty plugin install <path>` and approve the grant; `bitty plugin list` shows what is recorded.                                                                                              |
| `E_UI_ALREADY_CAPTURED` | `runtime`    | Another overlay already holds the single transient input-capture session.                                                | Close the other overlay, then toggle again. Palette degrades instead of throwing; the toggle returns a count with no visible overlay.                                                                |
| `E_COMMAND_INVALID`     | `validation` | The highlighted command's args schema rejects the empty argument table, or its result schema rejects the returned value. | An args rejection shows `Needs arguments: <title>`; a result rejection shows `Invocation refused: E_COMMAND_INVALID`. The overlay stays open. Argument entry is the separate follow-up (bitty#2965). |
| `E_COMMAND_GONE`        | `runtime`    | The command was registered but its owning generation is no longer active.                                                | The overlay shows `Invocation refused: E_COMMAND_GONE` and stays open. Reopen the palette after the owning plugin finishes reloading.                                                                |
| `E_COMMAND_UNKNOWN`     | `runtime`    | The highlighted catalog row no longer names a live command.                                                              | The overlay shows `Invocation refused: E_COMMAND_UNKNOWN` and stays open. Refresh with `focus.changed` or reopen the palette.                                                                        |
| `E_COMMAND_FAILED`      | `runtime`    | The command raised, was busy, or violated its result schema.                                                             | The overlay shows `Invocation refused: E_COMMAND_FAILED` and stays open. Check the owning plugin's diagnostics.                                                                                      |

A toggle that returns a count but shows nothing means capture acquisition was
refused: the grant is missing, another overlay holds the session, or the host
predates the capture table. A visible `Command list unavailable` row means the
host cannot serve `bitty.commands.list`; an empty catalog shows the `No
entries` placeholder, and a query with no match shows `No matches`. An
`Invocation unavailable` row means the host has no `bitty.commands.invoke`
surface, so the palette can list commands but cannot run them.

## Status

Pre-implementation ecosystem: the plugin package, manifest, and policy are
implemented and tested headlessly against the local mock host. The Bitty host
surfaces this package uses (`bitty.commands.list`, `bitty.commands.invoke`,
`bitty.ui.overlay.acquire`/`update`/`poll`/`release`, and the
`overlay.input.available` observation) are landed, but nothing here is a
compatibility promise beyond the manifest `[compat]` ranges.

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
  (`bitty.commands.list`, bounded by the host) across the command id, title,
  and owning plugin id;
- at most `128` matched entries (`MAX_ENTRIES`) and at most `12` visible rows
  per frame (`MAX_VISIBLE`); the selection window follows the highlight, and
  the match-count row reports the bounded matches against the scanned catalog;
- candidate input bounded to `1024` examined catalog rows per filter pass
  (`MAX_INPUT`); larger catalogs are cut at the bound and the cut is reported
  through the filter stats (`filter.filter_commands` returns
  `{ scanned, matched, truncated }` as its second value);
- a catalog the host cannot serve paints `Command list unavailable`, so a
  broken source is never mistaken for an empty one; a non-empty query with no
  match paints `No matches`;
- the declared `query` setting (default `""`) seeds the filter at open; live
  typing replaces it for the session and Backspace widens it;
- query truncated to `128` characters, display text truncated to the host
  overlay text bound `128` (`MAX_OVERLAY_TEXT_LEN`) at a UTF-8 code-point
  boundary;
- captured input is drained only on the cold path: the host publishes
  `overlay.input.available` while this capture owner has queued input, and the
  palette calls `bitty.ui.overlay.poll`; no plugin callback runs on the input
  hot path;
- Up/Down move the highlight with wrap-around; `j`/`k` do the same while the
  query is empty and become ordinary text once filtering starts; Enter invokes
  the highlighted command through `bitty.commands.invoke`, and Escape closes;
- a successful invocation closes the session with the `submitted` disposition;
  a refusal keeps the overlay open with a typed row: an empty-args schema
  rejection paints `Needs arguments: <title>` (the host validates before the
  callee body runs), and every other refusal paints
  `Invocation refused: <code>`;
- overlay content composed as a single declarative `List` of `Text` rows
  (`Text`, `Row`, `Column`, `List` are the only Plugin API v1 node kinds);
- every open acquires the focusable overlay plus transient input capture in
  one Core-owned switch
  (`bitty.ui.overlay.acquire({ title = "Palette", placeholder = "Filter commands" })`);
  the Core surfaces only the capture owner's block, so the acquire is what
  makes the overlay visible;
- the open scene is never empty: the title, live query, and match-count rows
  plus the visible command rows, or a placeholder row when the catalog is
  empty, unavailable, or unmatched — a real UI, not a bare pill;
- closing ends the session (`bitty.ui.overlay.release(handle, "cancelled")` or
  `"submitted"` after invocation), which destroys the surface; an involuntary
  session end (focus switch, idle timeout, unload) observed through
  `overlay.released` resets the toggle state so the next toggle re-opens;
- host capture and invocation calls are `pcall`-guarded: a denied focus grant,
  a live foreign session, or a host without the capture table degrades to
  command-only mode (counts still returned), a rejected session update keeps
  the last successfully presented scene, and a missing `bitty.commands.invoke`
  paints `Invocation unavailable` instead of throwing;
- `toggle` returns the number of matched entries (`0` when closing) and
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

- **Argument entry (bitty#2965).** The host command catalog serves
  `{ plugin, id, qualified, title }` only, with no args schema, so the palette
  cannot know before dispatch whether a command needs arguments. It invokes
  with `{}`; the host validates the empty table before any callee code runs and
  the palette reports `Needs arguments: <title>` on `E_COMMAND_INVALID`. A
  dedicated argument editor is the separate follow-up task.
- **No picker-provider API.** A picker-provider API is still draft/post-1.0;
  the host command catalog is the entry source.
- **`j`/`k` share the typing alphabet.** They navigate while the query is
  empty and type once filtering starts, so a query cannot begin with `j` or
  `k`. Up/Down remain unambiguous navigation keys.

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
`just test-luals` skips with exit 0 when absent. `just docs-check` fails when
the README Configuration table drifts from the manifest `[settings]`.

## Security

Only `ui.overlay.focus` is requested: one focusable overlay plus the bounded
transient input-capture session for one interaction. The plugin has no
filesystem, process, network, clipboard, terminal-input, or persistent-state
authority. It performs no I/O and spawns nothing. Command invocation is
host-mediated (`bitty.commands.invoke`): the palette never dispatches or
executes plugin code itself, and the host keeps its deny-by-default
registration, args-schema, and cross-VM containment checks. The
`overlay.input.available` observation carries no input bytes; captured keys
are drained by the owner through `bitty.ui.overlay.poll`. Report
vulnerabilities through the process in the umbrella project's security policy
rather than a public issue.
