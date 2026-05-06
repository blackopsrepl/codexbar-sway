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
