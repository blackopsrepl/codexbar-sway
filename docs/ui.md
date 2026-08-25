# UI

CodexBar has one human-facing UI: `frontend/quickshell/shell.qml`.

## Waybar Chip

Waybar calls:

```bash
codexbar waybar render
```

The payload includes:

- `text`: compact provider/quota text.
- `tooltip`: multiline detail.
- `class`: CSS classes for provider, health, and display mode.

Waybar does not render pace/reserve/hot text or pace classes. Pace detail remains available in the QuickShell panel.

The compact Codex chip renders every quota window present in the cached provider response. When a non-Pro ChatGPT account omits its expected five-hour value, the chip keeps that lane visible as `--` beside the real weekly percentage; the modal labels it unavailable. A missing weekly window stays absent, and the UI never turns a missing value into a fabricated percentage.

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
- Overview: active display provider, freshness, service/runtime/privacy state, and compact cards for enabled, visible overview providers
- Provider Detail: focused provider identity, quota hero, service/local/history/storage detail cards, model local usage rows when present, alerts, provider rail, and provider actions
- History: retained presenter history for the focused provider, including quota bars, local token summaries, and model detail when present
- Settings: cadence, display mode, notification, privacy, scan, and cache-clear controls

The panel sends mutations back through the Ruby CLI. It does not fetch provider usage directly.

Provider action controls queue CLI mutations instead of killing in-flight commands. Provider on/off, show/hide, overview, and auto-select changes update local config/snapshot state immediately; quota refresh remains daemon/refresh owned.

Runtime controls include manual, 1m, 2m, 5m, 15m, and 30m refresh cadence, notifications, privacy redaction, status refresh, local usage scan, storage scan, and cache clear commands.

## Fonts and Glyphs

The UI uses text plus Nerd Font glyph metadata from the Ruby provider metadata. Missing glyph support affects visual polish but not provider fetching.
