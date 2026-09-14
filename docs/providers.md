# Providers

The Linux release supports exactly:

- `codex`
- `claude`
- `gemini`
- `opencode`
- `zai`

## Codex

- Source label: `codex-cli`.
- Runtime path: `codex --sandbox read-only --ask-for-approval never app-server --stdio`.
- RPC methods:
  - `initialize`
  - `account/read`
  - `account/rateLimits/read`
- Dashboard: `https://chatgpt.com/codex`

CodexBar reads the `codex` entry from `rateLimitsByLimitId` when present and falls back to the backward-compatible `rateLimits` snapshot. It identifies the five-hour and weekly windows by their declared 300-minute and 10,080-minute durations instead of assuming that `primary` and `secondary` always retain fixed meanings. A missing weekly window remains absent. For non-Pro ChatGPT plans, an omitted five-hour value is surfaced as unavailable rather than converted into a fabricated percentage; Pro continues to expose only the windows returned for that account.

There is no PTY fallback in the current Ruby implementation.
Local token summaries are read from Codex session JSONL logs by `codexbar cost`; monetary cost is reported only when an exact cost exists in the source record.

## Claude

- Source label: `oauth`.
- Credentials: `~/.claude/.credentials.json`.
- Usage endpoint: `https://api.anthropic.com/api/oauth/usage`.
- Token refresh endpoint: `https://platform.claude.com/v1/oauth/token`.
- Dashboard: `https://claude.ai/`

There is no browser-cookie, secret-store, or CLI scrape in the current Ruby implementation.
Local token summaries are read from Claude project JSONL logs by `codexbar cost`; telemetry files are ignored.

## Gemini

- Source label: `api`.
- Credentials: `~/.gemini/oauth_creds.json`.
- Settings: `~/.gemini/settings.json`.
- OAuth client metadata: discovered from the installed Gemini CLI package or bundled Gemini CLI chunks.
- Project discovery: Code Assist project from `loadCodeAssist`, then Google Cloud project discovery when needed.
- Quota endpoint: `https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`.
- Local usage source: `~/.gemini/tmp/**/chats/*.jsonl`.
- Dashboard: `https://gemini.google.com/`

Gemini quota renders as separate model meters. Each quota bucket preserves the raw model id, for example `gemini-2.5-flash`, `gemini-2.5-pro`, and preview model ids returned by the API. The presenter may choose the highest-used model as the compact display meter, but it must keep all model buckets visible in detail and tooltip surfaces.

Retained history stays model-based: Gemini per-model quota is stored as `modelQuota` and model usage as `modelUsage`, and model buckets are never copied into the primary/secondary/tertiary window lanes. Days with no quota sample and no local usage are omitted from the History view.

Gemini local usage scans Gemini CLI chat JSONL records with `type: "gemini"` and `tokens` fields. Summaries preserve input, cached, output, reasoning/thought, tool, total, daily, and per-model token totals.

API-key and Vertex auth modes are not supported for quota in the current independent Linux implementation unless usable OAuth credentials are also present for Code Assist quota.

## OpenCode

- Source label: `opencode-go`.
- Credentials: `~/.local/share/opencode/auth.json` (the `opencode-go` API key, falling back to the `opencode` entry).
- Usage endpoint: `https://opencode.ai/zen/go/v1/usage`.
- Local usage source: `~/.local/share/opencode/opencode.db` (the OpenCode SQLite usage database).
- Dashboard: `https://opencode.ai/`

OpenCode Go exposes three subscription allowance windows as returned by the usage endpoint: `rolling` (five-hour), `weekly`, and `monthly`. Each window reports a used `percent` and a `resetsAt` timestamp. CodexBar maps `rolling` to the primary lane, `weekly` to the secondary lane, and `monthly` to the tertiary lane, matching the Codex window shape. Percentages are used percentages, matching the OpenCode console; a missing window stays absent.

OpenCode local usage is read from assistant messages in the OpenCode usage database. Each message contributes its input, cached read/write, output, and reasoning tokens plus monetary cost to the message's activity date and model id. This preserves model switches and sessions that span multiple days. The scanner groups these message records in SQLite before Ruby summarizes them, keeping refreshes bounded even for larger databases. Reading requires the `sqlite3` binary; when it is unavailable the provider is reported as unsupported rather than fabricated.

## Z.ai

- Source label: `zai-coding-plan`.
- Credentials: `ZAI_API_KEY` or `GLM_API_KEY`, falling back to the `zai-coding-plan` key in `~/.local/share/opencode/auth.json`.
- Quota endpoint: `https://api.z.ai/api/monitor/usage/quota/limit`.
- Dashboard: `https://z.ai/manage-apikey/coding-plan/personal/my-plan`

Z.ai tracks the GLM Coding Plan subscription allowance, not pay-as-you-go API credit. The quota endpoint returns a `limits` array of used-percentage windows; CodexBar reads each `TOKENS_LIMIT`/`CREDIT_LIMIT` entry and maps the five-hour unit (3) to the primary lane and the weekly unit (6) to the secondary lane. A monthly `TIME_LIMIT` entry maps to the tertiary lane when the account returns one; a missing window stays absent. Reset times are returned as epoch milliseconds. The account plan tier is shown in the provider identity.

Z.ai local usage is intentionally unsupported. The coding plan has no dedicated local token log, and usage run through OpenCode, Claude Code, or other tools is already attributed to those providers; CodexBar reports an unsupported local usage note instead of inventing or double-counting a source.

Browser-cookie scraping, WebKit probes, Keychain/libsecret integration, and providers outside `codex`, `claude`, `gemini`, `opencode`, and `zai` are out of scope for this release line.
