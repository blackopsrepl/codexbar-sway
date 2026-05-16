# CodexBar Repo Wireframe

## Purpose

This repository ships an independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete):

- Ruby backend for config, provider fetch, normalization, and runtime state.
- Resident daemon that writes cached snapshots.
- QuickShell panel as the only human-facing UI.
- Waybar JSON renderer for the compact bar chip.
- Deterministic user-prefix install through `Makefile`.
- Optional SolverForge Linux wrapper for the existing Waybar module.

Supported providers are exactly `codex`, `claude`, and `gemini`.

## Repository Map

### Runtime

- `bin/codexbar`: executable Ruby entrypoint.
- `lib/codexbar.rb`: top-level load file.
- `lib/codexbar/cli.rb`: command dispatcher and config mutation surface.
- `lib/codexbar/core/`: config version 5, provider metadata, formatting, metrics, process, HTTP.
- `lib/codexbar/providers/`: Codex, Claude, Gemini fetchers and registry.
- `lib/codexbar/runtime/daemon.rb`: provider refresh loop and Waybar signaling.
- `lib/codexbar/runtime/status.rb`: external service status cache for the supported providers.
- `lib/codexbar/runtime/local_usage.rb`: local Codex/Claude token usage scanner.
- `lib/codexbar/runtime/history.rb`: retained daily usage/history summaries.
- `lib/codexbar/runtime/storage.rb`: optional provider storage footprint scanner.
- `lib/codexbar/runtime/notifications.rb`: quota and incident notification transitions.
- `lib/codexbar/runtime/server.rb`: read-only cached localhost JSON server.
- `lib/codexbar/runtime/state.rb`: `snapshot.json` and `ui.json` ownership.
- `lib/codexbar/runtime/presenter.rb`: normalized view model for QuickShell and Waybar.
- `lib/codexbar/runtime/quickshell.rb`: QuickShell process and UI-state control.
- `lib/codexbar/runtime/waybar.rb`: cached Waybar render/action commands.
- `lib/codexbar/runtime/swaybar.rb`: bounded legacy direct-bar command, not the release UI.
- `frontend/quickshell/shell.qml`: panel UI.

### Install and Release

- `Makefile`: install, configure, validation, smoke, and SolverForge integration targets.
- `packaging/solverforge-linux/solverforge-waybar-codexbar`: checked-in source for the SolverForge Waybar wrapper.
- `bin/release-check`: canonical release validation script used by `make check`.
- `version.env`: current release version metadata.

### Documentation

- `README.md`: product overview, install, runtime command surface, and validation path.
- `AGENTS.md`: repo-local implementation, testing, documentation, and release rules.
- `WIREFRAME.md`: current repo/runtime/install map.
- `docs/installation.md`: install and rename-safety procedure.
- `docs/runtime-contracts.md`: config, snapshot, UI state, and Waybar contracts.
- `docs/architecture.md`: backend/frontend data flow.
- `docs/providers.md`: implemented provider fetch paths.
- `docs/cli.md`: command reference.
- `docs/configuration.md`: config fields and semantics.
- `docs/ui.md`: QuickShell and Waybar UI behavior.
- `docs/RELEASING.md`: release gates.

The top-level release truth is `README.md`, `AGENTS.md`, `WIREFRAME.md`, and `docs/`.

## Runtime Flow

1. User session or desktop starts `codexbar daemon --config ~/.codexbar/config.json`.
2. The daemon reads enabled providers from config.
3. Provider fetchers return raw usage payloads or explicit provider errors.
4. Auxiliary runtime modules refresh due status, local-usage, storage, notification, and history caches.
5. `Runtime::Usage` resolves the display provider, visible providers, overview providers, and auto-select candidates.
6. `Runtime::Presenter` builds the normalized view model.
7. `Runtime::State` writes `snapshot.json` under `runtime.stateDir`.
8. Waybar calls `codexbar waybar render` and reads cached state only.
9. Waybar clicks call the wrapper, which opens the QuickShell panel or refreshes.
10. QuickShell reads `snapshot.json` and `ui.json`, then sends mutations back through CLI commands.

The QuickShell panel has four views:

- Overview: active display provider, state badges, and compact cards for `codex`, `claude`, and `gemini`.
- Provider Detail: focused provider quota, status, local usage, history/storage summaries, alerts, provider rail, and provider actions.
- History: presenter-rendered retained daily history for the focused provider.
- Settings: cadence, display, notification, privacy, scan, and cache-clear controls.

## State Contracts

### Config

- Default path: `~/.codexbar/config.json`.
- Version: `5`.
- Provider fields: `id`, `enabled`, `visible`, `showInOverview`, `allowAutoSelect`, `source`.
- Display fields: `mergeIcons`, `showHighestUsage`, `showUsed`, `resetStyle`, `displayMode`, `metricPreferences`, `overviewProviders`, `selectedProvider`.
- Runtime fields: `refreshSeconds`, `refreshMode`, `notificationCommand`, `stateDir`, `waybarSignal`, `quickShellCommand`, `quickShellShell`.
- Auxiliary fields: `status`, `notifications`, `history`, `localUsage`, `storage`, `privacy`, `server`.

### Snapshot

- Default path: `~/.local/state/codexbar/snapshot.json`.
- Owned by Ruby runtime.
- Read by QuickShell and Waybar.
- Contains enabled/visible/hidden/overview/auto-select provider lists, selected/display provider ids, provider results, and rendered view data.
- Contains auxiliary `serviceStatus`, `localUsage`, `storage`, and `history` payloads.

### UI State

- Default path: `~/.local/state/codexbar/ui.json`.
- Owned by Ruby CLI commands.
- Read by QuickShell.
- Tracks whether the panel is open and which provider should be focused.

## Command Surface

### Runtime Commands

- `codexbar daemon`: run the resident refresh loop.
- `codexbar refresh`: fetch once and signal Waybar.
- `codexbar usage`: fetch usage directly for CLI output.
- `codexbar panel`: open QuickShell.
- `codexbar ui open|close|toggle|status`: control or inspect panel state.
- `codexbar waybar render|refresh|panel|cycle-next|cycle-prev`: Waybar render and action hooks.
- `codexbar status|cost|history|storage`: auxiliary cached status and local intelligence.
- `codexbar serve`: read-only local JSON endpoints.

### Config Commands

- `codexbar config init|validate`
- `codexbar providers list|activate|deactivate|show|hide|allow-auto|block-auto|pin|auto`
- `codexbar providers overview add|remove`
- `codexbar display status|used|remaining|mode`
- `codexbar runtime status|cadence`
- `codexbar notifications status|enable|disable`
- `codexbar privacy status|hide|show`
- `codexbar cache clear ...`
- `codexbar open dashboard codex|claude|gemini`

## Install Flow

1. `make install` copies a manifest of release files into `~/.local/share/codexbar`.
2. `make install` links `~/.local/bin/codexbar` to the installed entrypoint.
3. `make configure-user` creates config if missing.
4. `make configure-user` preserves user provider/display settings and updates only `runtime.quickShellShell`.
5. `make install-solverforge-linux-integration` installs the SolverForge wrapper only when explicitly requested.

After install/configure, the live desktop must not depend on the checkout directory path.

## Release Validation Flow

1. `make syntax`: Bash syntax plus per-file Ruby syntax checks.
2. `make test`: built-in Ruby test suite.
3. `make smoke`: config, Waybar render, and UI status smoke checks.
4. `make check`: canonical preview release gate via `bin/release-check`.
5. `make check-live`: credentialed stable release gate for Codex, Claude, and Gemini.

`make check-live` can fail because credentials or upstream provider auth are missing or invalid. That is a live release-environment blocker, not a regression in the local unit suite.

## Current Non-Goals

- no retired upstream desktop packaging flow
- no macOS runtime surface
- no Homebrew, Sparkle, or WebKit release path
- no Swift or TypeScript runtime
- no alternate CodexBar product fallback
- no providers outside the implemented Linux scope
- no provider fetches from Waybar
- no provider fetches from local server request handlers
- no broad install copy of the development checkout
