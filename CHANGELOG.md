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

### Changed

- Requests `ui.rich` in addition to `ui.overlay`: the accepted Plugin API v1
  Lua overlay path (`bitty.ui.mount`) requires both, unlike the bundled Rust
  realization which used the lower-level Panel Runtime overlay path.

[Unreleased]: https://github.com/bitty-terminal/palette/commits/main
