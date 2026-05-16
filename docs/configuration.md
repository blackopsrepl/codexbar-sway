# Configuration

CodexBar reads one JSON config file:

```text
~/.codexbar/config.json
```

The file is written with `0600` permissions.

## Shape

```json
{
  "version": 5,
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
    "refreshMode": "interval",
    "notificationCommand": "notify-send",
    "stateDir": "/home/user/.local/state/codexbar",
    "waybarSignal": 9,
    "quickShellCommand": "quickshell",
    "quickShellShell": "/home/user/.local/share/codexbar/frontend/quickshell/shell.qml"
  },
  "status": {
    "enabled": true,
    "refreshSeconds": 300
  },
  "notifications": {
    "enabled": false,
    "quotaWarnings": true,
    "incidentWarnings": true,
    "warningThreshold": 25,
    "criticalThreshold": 10,
    "restoredThreshold": 30
  },
  "history": {
    "enabled": true,
    "retentionDays": 30
  },
  "localUsage": {
    "enabled": true,
    "refreshSeconds": 900,
    "scanDays": 30
  },
  "storage": {
    "enabled": false,
    "refreshSeconds": 3600
  },
  "privacy": {
    "hidePersonalInfo": false
  },
  "server": {
    "host": "127.0.0.1",
    "port": 8765
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
- `refreshMode`: `interval` refreshes on `refreshSeconds`; `manual` keeps the daemon resident without periodic provider refreshes.
- `status`: polls external service-status feeds for the three supported providers.
- `notifications`: controls quota and incident desktop notifications through `runtime.notificationCommand`.
- `history`: retains daily cached quota/local-usage summaries.
- `localUsage`: scans local Codex and Claude logs for exact token/cost records.
- `storage`: optionally scans local provider state directories for footprint summaries.
- `privacy.hidePersonalInfo`: redacts account identity text in the UI.
- `server`: controls the read-only cached JSON server.

`make configure-user` preserves provider and display settings and updates only `runtime.quickShellShell`.

Supported provider IDs remain exactly `codex`, `claude`, and `gemini`.

Validate with:

```bash
codexbar config validate
```
