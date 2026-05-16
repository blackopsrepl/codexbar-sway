# UI

CodexBar has one human-facing UI: `frontend/quickshell/shell.qml`.

## Waybar Chip

Waybar calls:

```bash
codexbar waybar render
```

The payload includes:

- `text`: compact provider/quota/pace text.
- `tooltip`: multiline detail.
- `class`: CSS classes for provider, health, pace, and display mode.

Click behavior is provided by the desktop wrapper:

- left click: open QuickShell panel
- middle click: refresh
- right click: open QuickShell panel

## QuickShell Panel

The panel reads:

- `snapshot.json`
- `ui.json`

The panel renders:

- summary band
- view tabs for Overview, Provider Detail, History, and Settings
- Overview: active display provider, freshness, service/runtime/privacy state, and compact cards for `codex`, `claude`, and `gemini`
- Provider Detail: focused provider identity, quota hero, service/local/history/storage detail cards, alerts, provider rail, and provider actions
- History: retained presenter history for the focused provider, including quota bars and local token summaries when present
- Settings: cadence, display mode, notification, privacy, scan, and cache-clear controls

The panel sends mutations back through the Ruby CLI. It does not fetch provider usage directly.

Runtime controls include manual, 1m, 2m, 5m, 15m, and 30m refresh cadence, notifications, privacy redaction, status refresh, local usage scan, storage scan, and cache clear commands.

## Fonts and Glyphs

The UI uses text plus Nerd Font glyph metadata from the Ruby provider metadata. Missing glyph support affects visual polish but not provider fetching.
