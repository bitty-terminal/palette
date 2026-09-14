# Contributing to bitty-plugin-template

This guide is for contributors maintaining this template repository. The
repository is documentation-first and pre-implementation: everything here is
proposed governance scaffolding, not implemented product behavior. Guidance
aimed at plugin authors consuming generated output is out of scope until the
scaffold itself is accepted.

## Repository ground rules

- Read [AGENTS.md](AGENTS.md) before making any change. It defines authority,
  scope boundaries, CarryCtx workflow, toolchain policy, and the security
  constraints that override scaffolding convenience.
- The binding rules under [.carryctx/rules/](.carryctx/rules/) (delivery,
  documentation, security) apply to every agent and contributor.
- Canonical plugin architecture, API, packaging, compatibility, and security
  contracts live in `bitty-docs`. This repository must not invent capabilities,
  lifecycle semantics, or release policy independently.
- Never commit, push, publish packages, or mutate remote state without
  explicit authorization from the owning task.

## Prerequisites

Toolchain expectations (version pins live exclusively in the justfile and are
mirrored by [package.json](package.json); never invoke formatters or linters
by name):

- `just` — command runner owning all quality-gate invocations.
- `bun` / `bunx --bun` — JavaScript execution and package management. Never
  use `npm`, `npx`, or `yarn` in any Bitty repository.
- `markdownlint-cli2` — Markdown linting, configured by
  [.markdownlint-cli2.jsonc](.markdownlint-cli2.jsonc).
- `prettier` — formatting checks across the repository.
- `commitlint` — Conventional Commit message linting, configured by
  [commitlint.config.ts](commitlint.config.ts).
- `lefthook` — Git hook management, configured by
  [lefthook.yml](lefthook.yml).

No build, test, or generation steps exist in this repository yet.

## Development setup

1. Enter this repository before running Git, CarryCtx, or toolchain commands.
2. Install pinned development dependencies: `bun install`.
3. Enable Git hooks: `just hooks-install`.
4. Run all quality gates: `just check` (Markdown lint plus Prettier format
   check; CI runs the same aggregate target).
5. Record scoped work in CarryCtx (task, session, progress, checkpoint) and
   stop at review; independent review is required for acceptance.

## Delivery lifecycle

Changes follow Issue -> Branch -> Commit -> Pull Request -> Review -> Merge,
where independent review plus required CI must pass before merge.
Before this repository's first commit, branch/worktree/commit/pull-request
stages are unavailable: initialization happens in a shared checkout with
explicit disjoint scopes, preserved unrelated changes, and CI-equivalent
local checks, as described in [AGENTS.md](AGENTS.md).

Every pull request states its Issue and CarryCtx task links, impact areas
(generated tree, SDK/API, security, DX, CI/release, documentation,
compatibility), validation evidence, dependencies, and cross-repository
ordering. Documentation synchronization with canonical `bitty-docs` is part
of definition of done.

### Branch and worktree naming

Use the workspace-uniform convention for every task branch and worktree:

- Branches follow `ctx-XXXX/<type>-<short-slug>`, where `XXXX` is the owning
  CarryCtx task number, `<type>` is one of `feat|fix|chore|docs`, and the slug
  is short kebab-case (for example `ctx-0031/feat-isolation-rfc`).
- CarryCtx-bound worktrees live at `.worktrees/ctx-XXXX-<type>-<short-slug>`
  with `/` mapped to `-`.
- One branch per task. Commander housekeeping branches may use `cmd/<slug>`.

## Committing

Use Conventional Commits:

```text
feat(scaffold): add manifest example
docs(readme): clarify audience boundaries
chore(governance): wire lefthook hooks
```

Commit messages are validated by commitlint through the `commit-msg` hook
(`just hooks-install` enables it locally) and in CI-equivalent local runs of
`just commit-check`.

## Changelog

User-visible changes are recorded in [CHANGELOG.md](CHANGELOG.md) under
`[Unreleased]`, following the Keep a Changelog format.

## Reporting vulnerabilities

Do not open public issues for security vulnerabilities. Follow
[SECURITY.md](SECURITY.md) instead.
