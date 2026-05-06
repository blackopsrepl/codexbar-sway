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
codexbar open dashboard codex|claude|gemini
```

`codexbar bar` still exists as legacy direct-bar compatibility. The release path is QuickShell plus Waybar.

## Supported Providers

- `codex`
- `claude`
- `gemini`
