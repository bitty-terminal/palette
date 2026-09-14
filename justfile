# Quality gates for Palette (bitty-terminal.palette).
#
# Generated from bitty-plugin-template. Tool pins live here; there is no
# package.json or install step and every JavaScript tool goes through
# bun/bunx.

luaparse_pin := "0.3.1"

# List available recipes.
default:
    @just --list

# Validate bitty-plugin.toml against the accepted manifest contract.
# Transitional: replace with `bitty-plugin-lint` from bitty-plugin-sdk
# (R-SDK-2) once that CLI is published; the manifest schema is owned by
# bitty-docs, not by this repository.
manifest:
    bun scripts/validate-manifest.mjs bitty-plugin.toml

# Parse the Lua entry point with a pinned Lua 5.1 grammar parser.
lua:
    bunx --bun luaparse@{{luaparse_pin}} --quiet --file lua/palette/init.lua

# Aggregate gate run locally and in CI.
check: manifest lua
