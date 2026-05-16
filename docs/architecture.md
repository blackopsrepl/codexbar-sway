# Architecture Overview

## Layers

CodexBar has four active layers:

1. Ruby CLI entrypoint.
2. Ruby backend for config, provider fetch, normalization, and state.
3. Cached runtime files in `~/.local/state/codexbar`.
4. Auxiliary cached status, local usage, history, storage, and notification state.
5. QuickShell panel plus compact Waybar renderer.

## Entry Points

- `bin/codexbar`: loads `lib/` and runs `CodexBar::CLI`.
- `codexbar`: installed symlink to the installed entrypoint after `make install`.
- `codexbar daemon`: resident refresh loop.
- `codexbar waybar render`: Waybar JSON payload.
- `codexbar panel`: opens the QuickShell panel.

## Data Flow

1. `codexbar daemon` loads config.
2. Enabled providers are fetched through `lib/codexbar/providers`.
3. `Runtime::State` builds `snapshot.json`.
4. `Runtime::Presenter` builds view-ready data inside the snapshot.
5. Auxiliary runtime modules refresh due status/local-usage/storage caches and update history.
6. Waybar reads cached state through `codexbar waybar render`.
7. QuickShell watches `snapshot.json` and `ui.json`.
8. UI actions call back into `codexbar providers`, `codexbar display`, `codexbar refresh`, `codexbar runtime`, or `codexbar ui`.

Provider state commands are local config/snapshot mutations. They do not synchronously fetch provider usage; the daemon and explicit refresh command own quota fetches.

## Boundaries

- Provider fetchers do network/CLI/auth work.
- Runtime state owns files and locks.
- Status/local usage/history/storage modules own auxiliary caches.
- Presenter converts provider data into UI-ready structures.
- QuickShell presents state and invokes CLI commands.
- Waybar is a render and action surface only.
- The local HTTP server is read-only and serves cached state only.

See `docs/runtime-contracts.md` for exact file contracts.

## Out of Scope

- providers outside the implemented Linux scope
- browser-cookie scraping
- terminal product UI
- alternate launcher product flows
- macOS packaging/runtime
