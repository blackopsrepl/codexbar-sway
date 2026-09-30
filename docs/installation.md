# Installation

TokenMaxx installs as a user-prefix Linux tool. The install must not depend on the development checkout path.

## Prerequisites

- Ruby
- `rg` for development and validation targets
- `pre-commit` for `make check`
- QuickShell for the panel UI
- Waybar for the compact bar integration
- Provider credentials:
  - Codex CLI authenticated and able to run `codex app-server`
  - Claude credentials in `~/.claude/.credentials.json`
  - Gemini CLI OAuth credentials in `~/.gemini/oauth_creds.json`
  - OpenCode Go: `opencode-go` key in `~/.local/share/opencode/auth.json`, with local usage read from `~/.local/share/opencode/opencode.db`
  - Z.ai: `ZAI_API_KEY`/`GLM_API_KEY`, or the `zai-coding-plan` key in `~/.local/share/opencode/auth.json` (local usage reads Z.ai-routed messages from the same OpenCode database)
  - Ollama Cloud: `OLLAMA_API_KEY`, or the `ollama-cloud` key in `~/.local/share/opencode/auth.json` (local usage reads `ollama-cloud`-routed messages from the same OpenCode database)
  - Hermes Agent: no credential is needed; when `~/.hermes/state.db` exists it is read as an additional local usage source, so a provider driven through Hermes is counted cumulatively with the same provider driven through its own CLI

## Install

```bash
make install
make configure-user
```

Defaults:

- `PREFIX=$(HOME)/.local`
- app tree: `$(PREFIX)/share/tokenmaxx`
- CLI symlink: `$(PREFIX)/bin/tokenmaxx`
- config: `~/.config/tokenmaxx/config.json`

`make configure-user` creates config if missing and updates only:

```json
{
  "runtime": {
    "quickShellShell": "~/.local/share/tokenmaxx/frontend/quickshell/shell.qml"
  }
}
```

Existing provider and display settings are preserved.

## Restart After Install

`make install` replaces the installed directory, so the resident `tokenmaxx daemon` and the QuickShell panel keep executing the previously installed code until restarted — file watchers do not fire across the directory swap. Restart both before verifying behavior on the live desktop:

```bash
# restart the daemon (the SolverForge launcher also restarts it at session start)
pkill -f 'tokenmaxx daemon' && setsid nohup tokenmaxx daemon --config ~/.config/tokenmaxx/config.json >/dev/null 2>&1 &

# restart the panel (ui open respawns it when it is not running)
pkill -f 'tokenmaxx/frontend/quickshell/shell.qml'; tokenmaxx ui open
```

The installed version is recorded in `~/.local/share/tokenmaxx/version.env`.

## SolverForge Linux Waybar

SolverForge Linux owns the Sway and Waybar desktop config. TokenMaxx only provides a reproducible wrapper for the existing Waybar module:

```bash
make install-solverforge-linux-integration
```

This installs:

```text
~/.local/share/solverforge/bin/solverforge-waybar-tokenmaxx
```

The wrapper delegates to `~/.local/bin/tokenmaxx` by default and supports:

- `render`
- `open`
- `panel`
- `details`
- `refresh`

## Omarchy Shell Bar

On a Hyprland desktop running the Omarchy shell, mount the same chip as an Omarchy bar module:

```bash
tokenmaxx omarchy install
tokenmaxx omarchy status
tokenmaxx omarchy remove
```

`omarchy install` seeds `~/.config/omarchy/shell.json` from the Omarchy defaults when it does not exist, inserts the `tokenmaxx` command module (default: directly after `omarchy.weather`), and asks the running shell to reload. `--after ID`, `--section left|center|right`, `--index N`, `--interval SECONDS`, and `--exec PATH` override placement and the poll interval. The module polls `tokenmaxx waybar render`; it does not start the daemon, so launch that at session startup, for example from Hyprland:

```ini
exec-once = tokenmaxx daemon
```

## Rename Safety

Before renaming or moving the checkout, verify live integration no longer points at the checkout:

```bash
readlink -f ~/.local/bin/tokenmaxx
tokenmaxx ui status --format json --pretty
rg "<old checkout directory name>" ~/.config/tokenmaxx ~/.local/bin ~/.local/share/solverforge
```

Expected:

- `~/.local/bin/tokenmaxx` resolves inside `~/.local/share/tokenmaxx`.
- UI status reports `~/.local/share/tokenmaxx/frontend/quickshell/shell.qml`.
- The `rg` command has no live integration hits. Use the actual old checkout directory name when running it.

## Upgrading from CodexBar

TokenMaxx is the rebrand of this project (formerly CodexBar, repo `codexbar-sway`). A pre-rebrand install keeps working until you install TokenMaxx over it; after installing:

| CodexBar | TokenMaxx |
| --- | --- |
| `codexbar` CLI | `tokenmaxx` |
| `~/.codexbar/config.json` | `~/.config/tokenmaxx/config.json` |
| `~/.local/state/codexbar` | `~/.local/state/tokenmaxx` |
| `~/.local/share/codexbar` | `~/.local/share/tokenmaxx` |
| `CODEXBAR_BIN` / `CODEXBAR_CONFIG` / `CODEXBAR_STATE_DIR` | `TOKENMAXX_BIN` / `TOKENMAXX_CONFIG` / `TOKENMAXX_STATE_DIR` |

Behavior on first run:

- If `~/.config/tokenmaxx/config.json` does not exist and the legacy default config does, it is imported once. There is no fallback: the legacy path is never read again, and old files are left in place, not deleted.
- An imported config that still carries the legacy default `runtime.stateDir` (`~/.local/state/codexbar`) is remapped to the new default. Custom stateDir values are preserved.
- An explicit `--config` path is never auto-imported; release checks and scripts stay hermetic.
- `tokenmaxx omarchy remove` also removes bar modules installed under the legacy `codexbar` module id; `tokenmaxx omarchy install` writes the `tokenmaxx` id.

Restart the daemon and panel after upgrading (see "Restart After Install").

## Uninstall

```bash
make uninstall
```

This removes only the installed tree and the TokenMaxx CLI symlink if it points at that tree. It does not remove user config, state, or SolverForge Linux files.
