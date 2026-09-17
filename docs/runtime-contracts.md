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
- `localUsage.*`: local Codex, Claude, Gemini, OpenCode Go, and Z.ai scan controls; Z.ai reads its routed messages from the OpenCode usage database.
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

`view` is presenter-owned data for QuickShell and Waybar. Provider entries include view-ready quota metrics, explicit `unavailableMetrics`, a compact `quotaSummaryText`, service status text, local usage text, optional `localUsageModels`, storage text, retained `historyDays`, a `historyHeatmap` (dense week-aligned day cells with token intensity buckets, a `present` flag distinguishing retained-but-tokenless days from gaps, per-cell `tooltipText`, plus `stats` for window, active days, streak, best day, and peak), and `historySummary` so the QML panel does not parse raw provider payloads. An unavailable metric has no percentage and must not participate in severity, pace, or automatic provider selection.

## Auxiliary State

All files live under `runtime.stateDir`, are owned by Ruby, and are written with `0600` permissions:

- `status.json`: current external service state for Codex/OpenAI, Claude, and Gemini/Google Cloud.
- `local_usage.json`: exact local token/cost summaries from Codex and Claude logs plus Gemini CLI chat token summaries and OpenCode usage database summaries. Every provider summary can include a `models` map keyed by model id: Codex uses the session `turn_context` model, Claude the record `message.model`, and Gemini and OpenCode the source model id. Z.ai entries summarize Z.ai-routed assistant messages (`providerID` `zai-coding-plan`/`zai`) from the OpenCode usage database, and OpenCode Go entries summarize only assistant messages with `providerID` `opencode-go`, so Z.ai rows and other harness-routed providers are never attributed to OpenCode Go.
- `history.json`: daily retained quota/local-usage summaries. Window providers keep primary/secondary/tertiary samples; Gemini meter providers keep per-model quota in `modelQuota` and model usage in `modelUsage` keyed by raw model id without synthesizing window lanes. Local-usage fields (tokens, records, cost, `modelUsage`) are re-merged from the current scan window on every update, so a corrected local scanner repairs already-retained days. Days with neither a quota sample nor local usage are omitted from the presenter's `historyDays`, so a provider with no samples yields the History empty state.
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
