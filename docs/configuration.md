# Configuration

CodexBar reads one JSON config file:

```text
~/.codexbar/config.json
```

The file is written with `0600` permissions.

## Shape

```json
{
  "version": 4,
  "providers": [
    {
      "id": "codex",
      "enabled": true,
      "visible": true,
      "showInOverview": true,
      "allowAutoSelect": true,
      "source": "auto"
    }
  ],
  "display": {
    "showHighestUsage": true,
    "selectedProvider": "codex",
    "showUsed": false,
    "displayMode": "both"
  },
  "runtime": {
    "refreshSeconds": 120,
    "notificationCommand": "notify-send",
    "stateDir": "/home/user/.local/state/codexbar",
    "waybarSignal": 9,
    "quickShellCommand": "quickshell",
    "quickShellShell": "/home/user/.local/share/codexbar/frontend/quickshell/shell.qml"
  }
}
```

## Semantics

- `enabled`: provider is refreshed by the daemon.
- `visible`: provider appears in the main UI.
- `showInOverview`: provider can appear in the overview row.
- `allowAutoSelect`: provider can win automatic highest-usage display.
- `showHighestUsage`: automatic display mode vs pinned provider.
- `selectedProvider`: pinned provider.
- `showUsed`: used vs remaining percent phrasing.
- `displayMode`: `both`, `percent`, or `pace`.

`make configure-user` preserves provider and display settings and updates only `runtime.quickShellShell`.

Validate with:

```bash
codexbar config validate
```
