# Changelog

All notable changes to Bitty Palette (`bitty-terminal.palette`) are recorded
here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Independent first-party package extracted from the bundled
  `bitty-terminal.palette` realization (OQ-053 split decision, `bitty`
  `CTX-0397`).
- Pure-Lua palette: bounded filtering/truncation policy (`lua/palette/filter.lua`),
  declarative `List`/`Text` overlay composition (`lua/palette/scene.lua`), and
  the activation entry point (`lua/palette/init.lua`).
- Lua 5.4 behavior suite and LuaLS conformance.
- Adopt the canonical `.editorconfig` baseline (`CTX-0023` slice); the
  repository-metadata baseline guide and ADR-0011 remain Proposed.

### Changed

- Pin the repository toolchain metadata: `packageManager` is now `bun@1.4.2`,
  [CONTRIBUTING.md](CONTRIBUTING.md) documents the contributor-branch
  convention (`ctx-XXXX/<type>-<slug>`; external contributors use
  `<handle>/<type>-<slug>`) and the delivery lifecycle, [SECURITY.md](SECURITY.md)
  follows the canonical reporting structure, and `.gitattributes` normalizes
  text files to LF.

- Switch manifest validation to the authoritative `bitty-plugin-lint`
  (bitty-plugin-sdk, R-SDK-2), commit-pinned in `package.json` and `bun.lock`
  (`CTX-0005`). The justfile gains `just install`
  (`bun install --frozen-lockfile`) and a fail-closed `just deps` guard;
  `just manifest` now runs `bun run bitty-plugin-lint bitty-plugin.toml`, and
  `just check` runs offline once the dependencies are installed. `luaparse`
  becomes an installed devDependency so the Lua parser gate also runs offline.
- Realign package version `0.1.0` → `0.0.1` per bitty-docs decision DIR-019
  (everything pre-1.0-stable stays on the `0.0.x` line). No behavior change;
  no published tag or release existed, so no published artifact is downgraded.
- Requests `ui.rich` in addition to `ui.overlay`: the accepted Plugin API v1
  Lua overlay path (`bitty.ui.mount`) requires both, unlike the former bundled Rust
  realization which used the lower-level Panel Runtime overlay path.
- Reframe the palette envelope citations (`lua/palette/filter.lua`,
  `lua/palette/init.lua`, `README.md`, manifest and test comments): this
  package is the authoritative realization, and the historical bundled Rust
  realization (`crates/bitty-runtime/src/palette.rs`) was removed from `bitty`
  by PR #1611 (commit `67cdcc14`). Comment and prose only; no behavior change
  (`CTX-0008`).
- Replace the `ui.rich` + `ui.overlay` capability pair with the single coupled
  W-01 grant `ui.overlay.focus`, subscribe `overlay.released` alongside
  `focus.changed`, and move the SDK pin to `bitty-plugin-sdk#d5d117d`, which
  carries the W-01 identifiers transitively via its parent `e769117` (W-120,
  the first `ui.overlay.focus` commit), so `just manifest` validates the
  capture surface (bitty `bitty-terminal/bitty#1971`). The spec-acquire path
  needs only the focus grant; the v1 presentation-slot grants are unrequested.
  The vendored LuaLS definitions gain a marked hand-maintained W-01 amendment
  until the SDK projection covers the surface.

### Removed

- Delete the vendored transitional `scripts/validate-manifest.mjs`; the pinned
  SDK linter is now the single source of manifest validation (`CTX-0005`).
- Delete the redundant `tests/check-manifest-lint.mjs` wrapper and its
  `just test-manifest` recipe, which skipped with exit 0 when
  `bitty-plugin-lint` was undiscoverable; the fail-closed `just manifest` gate
  replaces it.

### Fixed

- Input bound: `filter.filter` examines at most `1024` candidate entries per
  pass (`MAX_INPUT`), reports the cut through a `{ scanned, truncated }` stats
  second return value, and fails closed on non-table input. Oversized
  `entries` settings no longer do unbounded work per toggle or focus change
  (R20).
- UI resilience: host UI calls are `pcall`-guarded; a denied capture degrades
  to command-only mode, a rejected update keeps the last-known-good scene, and
  neither crashes activation, the `toggle` command, nor the event handlers
  (R21, M-PAL-01).
- Toggle acquires the W-01 transient input capture on open and ships a
  non-empty default scene (bitty `bitty-terminal/bitty#1971`): every open
  calls `bitty.ui.overlay.acquire({ title, placeholder })` so the Core
  surfaces the session block, paints title plus filtered items (or the
  placeholder row when empty) with the session-owned update, and destroys the
  surface on `release("cancelled")`. Involuntary session ends observed through
  `overlay.released` reset the toggle state so the next toggle re-opens.
  Without the capture grant, on a conflicting session, or on a host without
  the capture table, the toggle degrades to command-only counts.
- Historical compatibility context only: earlier investigation recorded a
  `0.0.22-dev` host as carrying the v1 bridge, the W-01 capture mechanism, and
  the `overlay.released` event (bitty `bitty-terminal/bitty#1970`). This records
  the reviewed contract/candidate context and does not claim current runtime
  feature usability. The manifest's current compatibility floor is
  `>=0.0.24,<0.1`; the `<0.1` ceiling stays restrictive because `0.x` minors
  may break.
- `toggle` declares a closed empty-object `args_schema` and an integer
  `result_schema` matching the returned count, consistent with the Plugin API
  v1 command contract and the `activity` command style (R21, L-PAL-03).
- `toggle` close no longer renders twice: closing presents the empty scene in
  a single render and reports `0` displayed entries instead of rendering the
  filtered list first (M-PAL-02).
- Fix template-identity artifacts copied from `bitty-plugin-template`: the
  CodeQL configuration `name` (`.github/codeql/codeql-config.yml`), the
  `CONTRIBUTING.md` title, the `SECURITY.md` advisory URL, and the issue
  template descriptions.

[Unreleased]: https://github.com/bitty-terminal/palette/commits/main
