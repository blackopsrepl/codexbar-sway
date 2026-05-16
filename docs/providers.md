# Providers

The Linux release supports exactly:

- `codex`
- `claude`
- `gemini`

## Codex

- Source label: `codex-cli`.
- Runtime path: `codex -s read-only -a untrusted app-server`.
- RPC methods:
  - `initialize`
  - `account/read`
  - `account/rateLimits/read`
- Dashboard: `https://chatgpt.com/codex`

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
- Quota endpoint: `https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`.
- Dashboard: `https://gemini.google.com/`

API-key and Vertex auth modes are not supported by the current independent Linux implementation.
No trustworthy Gemini local usage log scanner is currently implemented.

Browser-cookie scraping, WebKit probes, Keychain/libsecret integration, and providers outside `codex`, `claude`, and `gemini` are out of scope for this release line.
