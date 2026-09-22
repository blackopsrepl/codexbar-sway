# Installation

CodexBar installs as a user-prefix Linux tool. The install must not depend on the development checkout path.

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

## Install

```bash
make install
make configure-user
```

Defaults:

- `PREFIX=$(HOME)/.local`
- app tree: `$(PREFIX)/share/codexbar`
- CLI symlink: `$(PREFIX)/bin/codexbar`
- config: `~/.codexbar/config.json`

`make configure-user` creates config if missing and updates only:

```json
{
  "runtime": {
    "quickShellShell": "~/.local/share/codexbar/frontend/quickshell/shell.qml"
  }
}
```

Existing provider and display settings are preserved.

## Restart After Install

`make install` replaces the installed directory, so the resident `codexbar daemon` and the QuickShell panel keep executing the previously installed code until restarted — file watchers do not fire across the directory swap. Restart both before verifying behavior on the live desktop:

```bash
# restart the daemon (the SolverForge launcher also restarts it at session start)
pkill -f 'codexbar daemon' && setsid nohup codexbar daemon --config ~/.codexbar/config.json >/dev/null 2>&1 &

# restart the panel (ui open respawns it when it is not running)
pkill -f 'codexbar/frontend/quickshell/shell.qml'; codexbar ui open
```

The installed version is recorded in `~/.local/share/codexbar/version.env`.

## SolverForge Linux Waybar

SolverForge Linux owns the Sway and Waybar desktop config. CodexBar only provides a reproducible wrapper for the existing Waybar module:

```bash
make install-solverforge-linux-integration
```

This installs:

```text
~/.local/share/solverforge/bin/solverforge-waybar-codexbar
```

The wrapper delegates to `~/.local/bin/codexbar` by default and supports:

- `render`
- `open`
- `panel`
- `details`
- `refresh`

## Omarchy Shell Bar

On a Hyprland desktop running the Omarchy shell, mount the same chip as an Omarchy bar module:

```bash
codexbar omarchy install
codexbar omarchy status
codexbar omarchy remove
```

`omarchy install` seeds `~/.config/omarchy/shell.json` from the Omarchy defaults when it does not exist, inserts the `codexbar` command module (default: directly after `omarchy.weather`), and asks the running shell to reload. `--after ID`, `--section left|center|right`, `--index N`, `--interval SECONDS`, and `--exec PATH` override placement and the poll interval. The module polls `codexbar waybar render`; it does not start the daemon, so launch that at session startup, for example from Hyprland:

```ini
exec-once = codexbar daemon
```

## Rename Safety

Before renaming or moving the checkout, verify live integration no longer points at the checkout:

```bash
readlink -f ~/.local/bin/codexbar
codexbar ui status --format json --pretty
rg "<old checkout directory name>" ~/.codexbar ~/.local/bin ~/.local/share/solverforge
```

Expected:

- `~/.local/bin/codexbar` resolves inside `~/.local/share/codexbar`.
- UI status reports `~/.local/share/codexbar/frontend/quickshell/shell.qml`.
- The `rg` command has no live integration hits. Use the actual old checkout directory name when running it.

## Uninstall

```bash
make uninstall
```

This removes only the installed tree and the CodexBar CLI symlink if it points at that tree. It does not remove user config, state, or SolverForge Linux files.
