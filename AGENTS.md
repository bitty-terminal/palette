# Bitty Palette repository guidance

## Repository and authority

- This is the independent `palette` repository. Its canonical remote is
  <https://github.com/bitty-terminal/palette>.
- The Bitty umbrella directory and `bitty-plugins` directory are grouping only;
  neither owns this repository's Git or CarryCtx state.
- Enter this repository before running Git, CarryCtx, validation, or toolchain
  commands.
- `bitty-docs` and `bitty-plugins-docs` are the canonical sources for plugin
  architecture, API, security, packaging, compatibility, and public-behavior
  contracts. This repository must not invent capabilities, lifecycle
  semantics, or release policy.
- The project is pre-implementation. Repository existence, a manifest, or a
  proposed file tree is not evidence of usable plugin behavior.

## Plugin identity and scope

- Plugin id: `bitty-terminal.palette` (manifest `plugin.id`), repository
  `palette`, Lua module `lua/palette/`.
- Purpose: command palette and picker UI via the overlay slot, using
  declarative list and text primitives only.
- Authority boundary: only `ui.rich` and `ui.overlay` are requested. No
  filesystem, process, network, clipboard, terminal input, or persistent-state
  authority; no install-time code execution. A wider request needs an
  explicitly scoped task and a reviewed security note; never widen silently.
- Origin: this package is the independent first-party realization created by
  the OQ-053 bundled-plugin split decision (`bitty` `CTX-0397`). The accepted
  Lua overlay path requires `ui.rich` in addition to the bundled
  realization's `ui.overlay`; that difference is recorded, not a capability
  widening done silently.

## CarryCtx and agents

- Use this repository's CarryCtx state for tasks, dependencies, scopes,
  sessions, progress, decisions, checkpoints, handoffs, and review.
- The commander coordinates. Delegate substantial scoped work to focused
  agents and require an independent reviewer for acceptance.
- Every agent reads its persona and applicable rules, binds a named session to
  the task, and stays within explicit scopes.
- After the first commit, prefer a dedicated branch and Git worktree for each
  independent task. Before it, shared-checkout initialization is allowed only
  for disjoint scopes with CI-equivalent local checks.
- Branch and worktree naming is uniform across repositories: branches use
  `ctx-XXXX/<type>-<short-slug>` where `XXXX` is the owning CarryCtx task
  number, `<type>` is one of feat|fix|chore|docs, and the slug is short
  kebab-case. CarryCtx-bound worktrees live at
  `.worktrees/ctx-XXXX-<type>-<short-slug>` with `/` mapped to `-`. One branch
  per task; commander housekeeping branches may use `cmd/<slug>`.
- Preserve unrelated changes. Do not commit, push, release, publish packages,
  create repositories, or mutate remote state without authorization.
- Fresh clones have no CarryCtx state DB. Restore the local DB from the
  in-repo snapshot branch with `just workflow-import` (validate-only:
  `just workflow-import-dry`). Snapshots are redacted publication artifacts
  from `carryctx export --publication`: never merge them back, and rotate at
  the source any secret that leaked before rotation.

## Delivery lifecycle

- The lifecycle is GitHub Issue, CarryCtx task, branch/worktree, commit, pull
  request, independent review plus CI, merge, then documentation
  synchronization, checkpoint, and task completion.
- Implementers stop at review. Independent review by a different agent plus
  required CI is the acceptance gate; green CI is not a substitute for review.
- Documentation synchronization is part of definition of done. Changes remain
  incomplete while affected canonical docs, reference, guides, risks, or
  release notes are stale.

## No hardcoded values

- Never hardcode host- or environment-specific values: absolute paths,
  usernames, hostnames, repository or mirror URLs, credentials, ports, or
  machine layout.
- Derive such values from configuration, environment variables, or the target
  repository's own metadata. Repository names and URLs come from the git
  remote or a parameter, never from literals duplicated across scripts.
- Tests, fixtures, docs, and scripts obey the same rule; durable artifacts
  must not embed a developer's checkout path.
- Use named constants for policy-bounded values (timeouts, limits, defaults).

## Toolchain policy

- Never use `npm`, `npx`, or `yarn` here. JavaScript execution and package
  management use `bun` / `bunx --bun` exclusively.
- Never invoke formatters, linters, or parsers directly by name. Run gates
  through the justfile: `just check`, `just fmt`, `just lint`, `just manifest`,
  `just lua`, `just test`.
- Version pins live in exactly one place per pin: the justfile for bunx tool
  pins, `package.json` + `bun.lock` for installed dev dependencies. Do not bump
  pins as a side effect of an unrelated task; report drift instead.
- CI success is a hard acceptance gate. Workflow-affecting changes are
  validated locally with `actionlint` before push.

## Security and supply chain

- The manifest, Lua sources, and any external input are untrusted data.
  Validate before use.
- No secrets, tokens, or local configuration in the repository, fixtures,
  logs, or CI output.
- Keep the requested capability set minimal and declared in
  `bitty-plugin.toml`; the manifest is the single source of the authority the
  plugin receives.

## Verification and handoff

- Keep edits inside the active CarryCtx scope and preserve unrelated work.
- Run `just check` plus `actionlint` on affected workflows and
  `gitleaks detect --source .` before concluding a change.
- Update this guide, `README.md`, `CHANGELOG.md`, and affected canonical docs
  whenever behavior, capabilities, or compatibility change.
