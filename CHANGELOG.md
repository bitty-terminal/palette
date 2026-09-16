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
- Lua 5.4 behavior suite, LuaLS conformance, and SDK manifest-lint wrapper.
- Adopt the canonical `.editorconfig` baseline (`CTX-0023` slice); the
  repository-metadata baseline guide and ADR-0011 remain Proposed.

### Changed

- Realign package version `0.1.0` → `0.0.1` per bitty-docs decision DIR-019
  (everything pre-1.0-stable stays on the `0.0.x` line). No behavior change;
  no published tag or release existed, so no published artifact is downgraded.
- Requests `ui.rich` in addition to `ui.overlay`: the accepted Plugin API v1
  Lua overlay path (`bitty.ui.mount`) requires both, unlike the bundled Rust
  realization which used the lower-level Panel Runtime overlay path.

### Fixed

- Input bound: `filter.filter` examines at most `1024` candidate entries per
  pass (`MAX_INPUT`), reports the cut through a `{ scanned, truncated }` stats
  second return value, and fails closed on non-table input. Oversized
  `entries` settings no longer do unbounded work per toggle or focus change
  (R20).
- UI resilience: `bitty.ui.mount` and `bitty.ui.update` are `pcall`-guarded;
  a denied mount degrades to command-only mode, a rejected update keeps the
  last-known-good scene, and neither crashes activation, the `toggle` command,
  nor the `focus.changed` handler (R21, M-PAL-01).
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
