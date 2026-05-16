# Repository Guidelines

## Current Product Contract
- CodexBar is a Linux-first Ruby application.
- Public docs should frame it as an independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete), not as a port.
- The supported runtime stack is Ruby + QuickShell + Waybar.
- The human-facing UI is `frontend/quickshell/shell.qml`.
- The QuickShell panel is organized into Overview, Provider Detail, History, and Settings views.
- Waybar is a compact launcher/render surface only.
- Provider fetches belong in the daemon and usage commands, not in Waybar.
- `snapshot.json` and `ui.json` are the backend/frontend runtime contract.
- Supported providers are exactly `codex`, `claude`, and `gemini`.

## Project Structure & Modules
- `bin/codexbar`: Ruby entrypoint.
- `bin/release-check`: canonical release validation script used by `make check`.
- `lib/codexbar/core`: config, types, formatting, process, HTTP, and metric logic.
- `lib/codexbar/providers`: Codex, Claude, Gemini fetchers and registry.
- `lib/codexbar/runtime`: daemon, snapshot state, presenter, QuickShell control, Waybar JSON, and the bounded legacy direct-bar command.
- `frontend/quickshell/shell.qml`: the only human-facing UI.
- `packaging/solverforge-linux`: reproducible SolverForge Linux Waybar wrapper integration.
- `docs`: current Linux release documentation only.

## Install, Build, Test, Run
- Install: `make install`
- Configure user install: `make configure-user`
- Install SolverForge Waybar wrapper: `make install-solverforge-linux-integration`
- Syntax check: `make syntax`
- Test suite: `make test`
- CLI smoke: `make smoke`
- Full release check: `make check`
- Stable live-provider check: `make check-live`
- Source-tree panel load: `make quickshell-load`

`make install` copies a manifest into `~/.local/share/codexbar` and links `~/.local/bin/codexbar`. `make configure-user` must preserve provider/display settings and update only `runtime.quickShellShell`.

## Coding Style & Naming
- Ruby only. Do not reintroduce Swift, TypeScript, or alternate UI/runtime stacks.
- Use ASCII unless the file already depends on Unicode; Nerd Font glyphs in UI metadata are intentional.
- Keep modules small and explicit; prefer pure functions in `core/` and `runtime/presenter.rb`.
- Preserve the current config vocabulary: `enabled`, `visible`, `showInOverview`, `allowAutoSelect`, `showHighestUsage`.
- Current config version is `5`.
- Do not add fallback provider systems, fallback UI launchers, or silent compatibility aliases.

## Runtime Boundaries
- `codexbar daemon` fetches enabled providers and writes cached snapshots.
- `codexbar refresh` performs an explicit fetch and signals Waybar.
- `codexbar waybar render` reads cached state only and emits Waybar JSON.
- `codexbar panel` opens QuickShell through `runtime.quickShellCommand` and `runtime.quickShellShell`.
- `codexbar ui open|close|toggle|status` mutates or reports `ui.json`.
- `codexbar serve` exposes cached state through read-only localhost JSON endpoints; request handlers must not fetch providers.
- `codexbar status`, `codexbar cost`, `codexbar history`, and `codexbar storage` operate on auxiliary runtime caches for the three supported providers only.
- `codexbar providers ...` and `codexbar display ...` are the supported config mutation surfaces.
- `codexbar bar` still exists as legacy direct-bar compatibility; it is not the release UI path.

## Testing Guidelines
- Add regression tests under `test/` using the built-in Ruby test stack.
- Prefer testing normalization, selection logic, snapshot building, presenter output, and Waybar payloads without hitting live provider credentials.
- Treat live provider checks as smoke tests, not as the primary regression suite.
- `make syntax` must check each Ruby source file separately.
- Run `make test` before handoff and `make check` before release.
- Run `make check-live` only when the machine has working Codex, Claude, and Gemini credentials.

## Documentation Guidelines
- Keep `README.md`, `AGENTS.md`, `WIREFRAME.md`, and `docs/` aligned with the Ruby code.
- Do not describe retired upstream packaging, macOS runtime, Homebrew, Sparkle, WebKit, Swift, TypeScript, kitty, wofi, or unsupported providers as current surfaces.
- Do not call the project a port; use "independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete)" when attribution is needed.
- If a command or config key changes, update the README, CLI docs, runtime-contract docs, and wireframe in the same change.
- If install behavior changes, update `Makefile`, `docs/installation.md`, README install steps, and the wireframe install flow together.
- If runtime state changes, update `docs/runtime-contracts.md` and the QuickShell/Waybar descriptions together.

## Commit & PR Guidelines
- Use scoped, descriptive conventional commits.
- Keep commits atomic: docs, tests, UI behavior, install behavior, and provider logic should be separated unless tightly coupled.
- Include the validation commands you ran in handoff notes.

## Agent Notes
- The top-level release truth is `README.md`, `AGENTS.md`, `WIREFRAME.md`, and `docs/`.
- Normal install must stay independent of SolverForge Linux desktop config.
- Use `make install-solverforge-linux-integration` for the explicit local SolverForge wrapper.
- Do not move provider fetching into Waybar.
- Do not make the checkout path part of the live desktop contract; install before renaming or moving this directory.
