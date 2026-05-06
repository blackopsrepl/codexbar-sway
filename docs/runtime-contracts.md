# Runtime Contracts

CodexBar uses files and CLI commands as the boundary between the Ruby backend, QuickShell, and Waybar.

## Config

Location:

```text
~/.codexbar/config.json
```

Important fields:

- `version`: current config version.
- `providers[]`: `id`, `enabled`, `visible`, `showInOverview`, `allowAutoSelect`, `source`.
- `display.showHighestUsage`: automatic highest-usage display mode.
- `display.selectedProvider`: pinned provider when automatic mode is off.
- `display.showUsed`: used vs remaining percent.
- `display.displayMode`: `both`, `percent`, or `pace`.
- `runtime.refreshSeconds`: daemon cadence.
- `runtime.stateDir`: state directory.
- `runtime.waybarSignal`: RT signal for Waybar repaint.
- `runtime.quickShellCommand`: QuickShell executable.
- `runtime.quickShellShell`: installed QML entrypoint.

## Snapshot

Location:

```text
~/.local/state/codexbar/snapshot.json
```

Current shape:

```json
{
  "snapshotVersion": 2,
  "generatedAt": "2026-05-06T00:00:00Z",
  "enabledProviders": ["codex"],
  "visibleProviders": ["codex"],
  "hiddenProviders": [],
  "overviewProviders": ["codex"],
  "autoSelectableProviders": ["codex"],
  "selectedProvider": "codex",
  "displayProvider": "codex",
  "results": {},
  "view": {}
}
```

The Ruby runtime owns this file. QuickShell reads it; QuickShell must not reimplement provider fetching.

## UI State

Location:

```text
~/.local/state/codexbar/ui.json
```

Shape:

```json
{
  "open": false,
  "focusProvider": "",
  "requestedAt": ""
}
```

Ruby CLI commands write this file when opening, closing, or focusing the panel.

## Waybar Payload

Command:

```bash
codexbar waybar render
```

Shape:

```json
{
  "text": "CX 97% reserve",
  "tooltip": "Display: Codex",
  "class": ["codexbar", "provider-codex", "healthy"]
}
```

Waybar reads cached state only. It must not fetch providers directly.
