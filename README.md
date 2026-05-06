<p align="center">
  <img src="./codexbar-mascot.png" alt="CodexBar mascot" width="320" />
</p>

# CodexBar

CodexBar is a Linux-first quota bar for Codex, Claude, and Gemini. It is an independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete).

The current product is a Ruby CLI/backend, a resident snapshot daemon, a compact Waybar JSON renderer, and one QuickShell panel. The supported runtime is Ruby + QuickShell + Waybar.

## Current Contract

- Runtime language: Ruby.
- Human-facing UI: `frontend/quickshell/shell.qml`.
- Bar surface: Waybar calls `codexbar waybar render` and receives cached JSON.
- Background fetch path: `codexbar daemon` fetches providers and writes snapshots.
- State files: `snapshot.json` and `ui.json` under `runtime.stateDir`, defaulting to `~/.local/state/codexbar`.
- Config file: `~/.codexbar/config.json`, current config version `4`.
- Supported providers: `codex`, `claude`, and `gemini`.

Provider fetches do not run inside Waybar. Waybar is only a render/action surface.

## Install

```bash
make install
make configure-user
```

By default this installs to:

- app tree: `~/.local/share/codexbar`
- CLI: `~/.local/bin/codexbar`
- config: `~/.codexbar/config.json`
- state: `~/.local/state/codexbar`

`make configure-user` creates the config if missing, preserves provider and display settings, and updates only `runtime.quickShellShell` to the installed QuickShell file.

For SolverForge Linux Waybar integration:

```bash
make install-solverforge-linux-integration
```

That installs the checked-in wrapper used by the existing SolverForge Waybar module. The normal product install does not edit SolverForge desktop config.

## Runtime

Core commands:

```bash
codexbar daemon
codexbar refresh
codexbar usage --provider codex,claude,gemini --format json --pretty
codexbar config validate
codexbar waybar render
codexbar panel
codexbar ui open|close|toggle|status
```

Provider controls:

```bash
codexbar providers list
codexbar providers activate codex
codexbar providers deactivate claude
codexbar providers show gemini
codexbar providers hide gemini
codexbar providers pin codex
codexbar providers auto
codexbar providers overview add claude
codexbar providers overview remove claude
codexbar providers allow-auto gemini
codexbar providers block-auto gemini
```

Display controls:

```bash
codexbar display status
codexbar display used
codexbar display remaining
codexbar display mode both
codexbar display mode percent
codexbar display mode pace
```

All providers are present in the default config, but provider entries default to disabled. Activate the providers this machine should fetch.

`codexbar bar` remains in the codebase as a bounded legacy direct-bar command. It is not the release UI path.

## Source-Tree Development

```bash
bin/codexbar config validate
bin/codexbar waybar render
bin/codexbar ui status --format json --pretty
```

Open the panel from the checkout:

```bash
env QT_QPA_PLATFORM=wayland \
  CODEXBAR_BIN=$PWD/bin/codexbar \
  CODEXBAR_CONFIG=$HOME/.codexbar/config.json \
  CODEXBAR_STATE_DIR=$HOME/.local/state/codexbar \
  quickshell --path $PWD/frontend/quickshell/shell.qml
```

Do not run the live desktop from the checkout if the checkout directory may be renamed. Install first, then run `make configure-user` so the user config points at the installed QuickShell path.

## Supported Providers

The release surface is exactly:

- `codex`
- `claude`
- `gemini`

Other providers are not part of this Linux release.

## Validation

```bash
make syntax
make test
make smoke
make check
```

`make check` delegates to `bin/release-check`. It runs pre-commit, Bash syntax, per-file Ruby syntax, the Ruby test suite, config/smoke checks, Waybar render, UI status, and QuickShell load when QuickShell is available.

Stable release validation on a credentialed machine:

```bash
make check-live
```

`make check-live` requires working live credentials for Codex, Claude, and Gemini. Credential or upstream auth failures are release-environment blockers, not unit-test failures.

## Documentation

- `AGENTS.md`: repo-local implementation and release rules.
- `WIREFRAME.md`: current runtime, install, and UI contract map.
- `docs/installation.md`: install and SolverForge Linux integration.
- `docs/runtime-contracts.md`: config, snapshot, UI, and Waybar JSON contracts.
- `docs/architecture.md`: runtime architecture.
- `docs/providers.md`: implemented provider fetch paths.
- `docs/cli.md`: command reference.
- `docs/RELEASING.md`: release gates.
