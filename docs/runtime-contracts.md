# Runtime Contracts

CodexBar uses files and CLI commands as the boundary between the Ruby backend, QuickShell, and Waybar.

## Config

Location:

```text
~/.codexbar/config.json
```

Important fields:

- `version`: current config version, currently `5`.
- `providers[]`: `id`, `enabled`, `visible`, `showInOverview`, `allowAutoSelect`, `source`.
- `display.showHighestUsage`: automatic highest-usage display mode.
- `display.selectedProvider`: pinned provider when automatic mode is off.
- `display.showUsed`: used vs remaining percent.
- `display.displayMode`: `both`, `percent`, or `pace`.
- `runtime.refreshSeconds`: daemon cadence.
- `runtime.refreshMode`: `interval` or `manual`.
- `runtime.stateDir`: state directory.
- `runtime.waybarSignal`: RT signal for Waybar repaint.
- `runtime.quickShellCommand`: QuickShell executable.
- `runtime.quickShellShell`: installed QML entrypoint.
- `status.enabled`, `status.refreshSeconds`: external status polling.
- `notifications.*`: quota and incident notification settings.
- `history.*`: daily snapshot retention.
- `localUsage.*`: local Codex, Claude, and Gemini log scan controls.
- `storage.*`: provider storage footprint scan controls.
- `privacy.hidePersonalInfo`: redacts identity text in the UI.
- `server.host`, `server.port`: read-only local JSON server binding.

## Snapshot

Location:

```text
~/.local/state/codexbar/snapshot.json
```

Current shape:

```json
{
  "snapshotVersion": 3,
  "generatedAt": "2026-05-06T00:00:00Z",
  "enabledProviders": ["codex"],
  "visibleProviders": ["codex"],
  "hiddenProviders": [],
  "overviewProviders": ["codex"],
  "autoSelectableProviders": ["codex"],
  "selectedProvider": "codex",
  "displayProvider": "codex",
  "serviceStatus": {},
  "localUsage": {},
  "storage": {},
  "history": {},
  "results": {},
  "view": {}
}
```

The Ruby runtime owns this file. QuickShell reads it; QuickShell must not reimplement provider fetching.

When a provider refresh fails after a successful sample, the daemon retains that provider's last good `usage` and `credits`, records the current error, and adds a note that cached quota is being shown. The original usage timestamp remains authoritative, so consumers can distinguish cached quota from a fresh provider response.

`view` is presenter-owned data for QuickShell and Waybar. Provider entries include view-ready quota metrics, service status text, local usage text, optional `localUsageModels`, storage text, retained `historyDays`, and `historySummary` so the QML panel does not parse raw provider payloads.

## Auxiliary State

All files live under `runtime.stateDir`, are owned by Ruby, and are written with `0600` permissions:

- `status.json`: current external service state for Codex/OpenAI, Claude, and Gemini/Google Cloud.
- `local_usage.json`: exact local token/cost summaries from Codex and Claude logs plus Gemini CLI chat token summaries. Gemini entries can include a `models` map keyed by raw model id.
- `history.json`: daily retained quota/local-usage summaries. Gemini meter providers can include `modelQuota` and `modelUsage` maps keyed by raw model id.
- `storage.json`: optional provider storage footprint summaries.
- `notification_state.json`: last notification state to prevent repeated alerts.

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
  "text": "CX 97%",
  "tooltip": "Display: Codex",
  "class": ["codexbar", "provider-codex", "healthy"]
}
```

Waybar reads cached state only. It must not fetch providers directly.
Waybar text omits pace/reserve/hot labels and pace classes; those remain modal-only detail.

## Local Server

`codexbar serve` exposes read-only cached JSON endpoints on `server.host:server.port`:

- `/health`
- `/usage`
- `/status`
- `/cost`
- `/history`
- `/storage`

Request handlers read existing cache files only.
