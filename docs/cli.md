# TokenMaxx CLI

Installed entrypoint:

```bash
tokenmaxx
```

Source-tree entrypoint:

```bash
bin/tokenmaxx
```

Default config: `~/.config/tokenmaxx/config.json`.

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
tokenmaxx usage
tokenmaxx refresh
tokenmaxx daemon
tokenmaxx panel
tokenmaxx ui open|close|toggle|status
tokenmaxx waybar render|refresh|panel|cycle-next|cycle-prev
tokenmaxx omarchy install|remove|status
tokenmaxx providers list
tokenmaxx providers activate <id>
tokenmaxx providers deactivate <id>
tokenmaxx providers show <id>
tokenmaxx providers hide <id>
tokenmaxx providers allow-auto <id>
tokenmaxx providers block-auto <id>
tokenmaxx providers overview add <id>
tokenmaxx providers overview remove <id>
tokenmaxx providers pin <id>
tokenmaxx providers auto
tokenmaxx display status
tokenmaxx display used
tokenmaxx display remaining
tokenmaxx display mode both|percent|pace
tokenmaxx config init
tokenmaxx config validate
tokenmaxx config dump
tokenmaxx open dashboard codex|claude|gemini|opencode|zai|ollama
tokenmaxx runtime status
tokenmaxx runtime cadence manual
tokenmaxx runtime cadence interval 60
tokenmaxx notifications status|enable|disable
tokenmaxx privacy status|hide|show
tokenmaxx status [--cached]
tokenmaxx cost [--cached]
tokenmaxx history
tokenmaxx storage [--cached]
tokenmaxx cache clear status|history|cost|storage|snapshot|notifications|all
tokenmaxx serve [--host 127.0.0.1] [--port 8765]
```

`tokenmaxx bar` still exists as legacy direct-bar compatibility. The release path is QuickShell plus Waybar.

`tokenmaxx omarchy install` mounts the Waybar chip as an Omarchy shell bar command module in `~/.config/omarchy/shell.json`, by default after `omarchy.weather`; it seeds the user file from the Omarchy defaults when missing. Flags: `--after ID`, `--section left|center|right`, `--index N`, `--interval SECONDS` (default 10), `--exec PATH`. `omarchy status` reports the installed module, and `omarchy remove` drops it.

`tokenmaxx serve` is read-only and serves cached state at `/health`, `/usage`, `/status`, `/cost`, `/history`, and `/storage`.

`--cached` avoids network or filesystem scans where a command supports an explicit refresh path.

Provider activation, deactivation, show/hide, overview, and auto-select commands mutate local config and cached snapshot state immediately. They do not synchronously fetch provider quota; use `tokenmaxx refresh` or `tokenmaxx usage` for explicit provider fetches.

## Supported Providers

- `codex`
- `claude`
- `gemini`
- `opencode`
- `zai`
