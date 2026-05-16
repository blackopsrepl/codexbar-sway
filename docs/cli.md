# CodexBar CLI

Installed entrypoint:

```bash
codexbar
```

Source-tree entrypoint:

```bash
bin/codexbar
```

Default config: `~/.codexbar/config.json`.

## Global Flags

- `--config <path>`
- `--format text|json`
- `--pretty`
- `--json`
- `--cached`
- `--host <host>`
- `--port <port>`
- `--once`
- `--provider <id[,id...]>`

## Commands

```bash
codexbar usage
codexbar refresh
codexbar daemon
codexbar panel
codexbar ui open|close|toggle|status
codexbar waybar render|refresh|panel|cycle-next|cycle-prev
codexbar providers list
codexbar providers activate <id>
codexbar providers deactivate <id>
codexbar providers show <id>
codexbar providers hide <id>
codexbar providers allow-auto <id>
codexbar providers block-auto <id>
codexbar providers overview add <id>
codexbar providers overview remove <id>
codexbar providers pin <id>
codexbar providers auto
codexbar display status
codexbar display used
codexbar display remaining
codexbar display mode both|percent|pace
codexbar config init
codexbar config validate
codexbar config dump
codexbar open dashboard codex|claude|gemini
codexbar runtime status
codexbar runtime cadence manual
codexbar runtime cadence interval 60
codexbar notifications status|enable|disable
codexbar privacy status|hide|show
codexbar status [--cached]
codexbar cost [--cached]
codexbar history
codexbar storage [--cached]
codexbar cache clear status|history|cost|storage|snapshot|notifications|all
codexbar serve [--host 127.0.0.1] [--port 8765]
```

`codexbar bar` still exists as legacy direct-bar compatibility. The release path is QuickShell plus Waybar.

`codexbar serve` is read-only and serves cached state at `/health`, `/usage`, `/status`, `/cost`, `/history`, and `/storage`.

`--cached` avoids network or filesystem scans where a command supports an explicit refresh path.

Provider activation, deactivation, show/hide, overview, and auto-select commands mutate local config and cached snapshot state immediately. They do not synchronously fetch provider quota; use `codexbar refresh` or `codexbar usage` for explicit provider fetches.

## Supported Providers

- `codex`
- `claude`
- `gemini`
