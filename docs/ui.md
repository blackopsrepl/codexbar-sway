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
- overview cards
- focused provider detail
- provider rail
- display/provider controls

The panel sends mutations back through the Ruby CLI. It does not fetch provider usage directly.

## Fonts and Glyphs

The UI uses text plus Nerd Font glyph metadata from the Ruby provider metadata. Missing glyph support affects visual polish but not provider fetching.
