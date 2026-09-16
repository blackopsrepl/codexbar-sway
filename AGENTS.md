# Repository Guidelines

## Current Product Contract
- CodexBar is a Linux-first Ruby application.
- Public docs should frame it as an independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete), not as a port.
- The supported runtime stack is Ruby + QuickShell + Waybar.
- The human-facing UI is `frontend/quickshell/shell.qml`.
- The QuickShell panel is organized into Overview, Provider Detail, History, and Settings views.
- Waybar is a compact launcher/render surface only.
- Waybar text is compact provider quota percentage text; do not put pace/reserve/hot labels or pace CSS classes in the bar.
- Provider fetches belong in the daemon and usage commands, not in Waybar.
- `snapshot.json` and `ui.json` are the backend/frontend runtime contract.
- Supported providers are exactly `codex`, `claude`, `gemini`, `opencode`, and `zai`.
- Gemini quota must stay model-meter based. Preserve each CLI/API model bucket instead of collapsing Gemini into a single Pro/Flash pair.
- Gemini local usage must come from deterministic Gemini CLI chat JSONL records or an explicitly documented telemetry file. Do not add browser scraping, cookie scraping, or silent API-key/Vertex quota fallbacks.
- Z.ai quota is the GLM Coding Plan subscription allowance from `https://api.z.ai/api/monitor/usage/quota/limit`, not pay-as-you-go API credit. Its API key comes from `ZAI_API_KEY`/`GLM_API_KEY` or the `zai-coding-plan` entry in `~/.local/share/opencode/auth.json`. Z.ai local usage is read from the OpenCode usage database by filtering assistant messages whose provider is `zai-coding-plan` or `zai`; OpenCode Go local usage is read from the same database but only from assistant messages whose provider is `opencode-go`, so other harness-routed providers (OpenAI/ChatGPT, Moonshot/Kimi, free Zen `opencode` models) and Z.ai rows are never attributed to OpenCode Go.
- Provider ids are stable config keys: `opencode` is the OpenCode Go subscription provider (display label `OpenCode Go`), and `zai` is the GLM Coding Plan provider. Change labels freely; never rename ids for a label change.

## Project Structure & Modules
- `bin/codexbar`: Ruby entrypoint.
- `bin/release-check`: canonical release validation script used by `make check`.
- `lib/codexbar/core`: config, types, formatting, process, HTTP, and metric logic.
- `lib/codexbar/providers`: Codex, Claude, Gemini, OpenCode, and Z.ai fetchers and registry.
- `lib/codexbar/runtime`: daemon, snapshot state, presenter, QuickShell control, Waybar JSON, and the bounded legacy direct-bar command.
- `frontend/quickshell/shell.qml`: the only human-facing UI.
- `packaging/solverforge-linux`: reproducible SolverForge Linux Waybar wrapper integration.
- `docs`: current Linux release documentation only.

## Install, Build, Test, Run
- Install: `make install`
- Configure user install: `make configure-user`
- Install SolverForge Waybar wrapper: `make install-solverforge-linux-integration`
- Syntax check: `make syntax`
- Test suite: `make test`
- CLI smoke: `make smoke`
- Full release check: `make check`
- Stable live-provider check: `make check-live`
- Source-tree panel load: `make quickshell-load`

`make install` copies a manifest into `~/.local/share/codexbar` and links `~/.local/bin/codexbar`. `make configure-user` must preserve provider/display settings and update only `runtime.quickShellShell`.

## Coding Style & Naming
- Ruby only. Do not reintroduce Swift, TypeScript, or alternate UI/runtime stacks.
- Use ASCII unless the file already depends on Unicode; Nerd Font glyphs in UI metadata are intentional.
- Keep modules small and explicit; prefer pure functions in `core/` and `runtime/presenter.rb`.
- Preserve the current config vocabulary: `enabled`, `visible`, `showInOverview`, `allowAutoSelect`, `showHighestUsage`.
- Current config version is `5`.
- Do not add fallback provider systems, fallback UI launchers, or silent compatibility aliases.

## Runtime Boundaries
- `codexbar daemon` fetches enabled providers and writes cached snapshots.
- `codexbar refresh` performs an explicit fetch and signals Waybar.
- `codexbar waybar render` reads cached state only and emits Waybar JSON.
- `codexbar panel` opens QuickShell through `runtime.quickShellCommand` and `runtime.quickShellShell`.
- `codexbar ui open|close|toggle|status` mutates or reports `ui.json`.
- `codexbar serve` exposes cached state through read-only localhost JSON endpoints; request handlers must not fetch providers.
- `codexbar status`, `codexbar cost`, `codexbar history`, and `codexbar storage` operate on auxiliary runtime caches for the supported providers only.
- `codexbar providers ...` and `codexbar display ...` are the supported config mutation surfaces. Provider activation, deactivation, show/hide, overview, and auto-select commands are immediate local config/snapshot updates; they must not synchronously fetch provider quota.
- `codexbar bar` still exists as legacy direct-bar compatibility; it is not the release UI path.

## UI Rules
- QuickShell Overview must render enabled, visible, `showInOverview` providers only, with no fixed provider cap.
- The provider rail may show all configured providers so inactive or hidden providers can be managed.
- Provider action controls should queue rather than kill in-flight CLI actions.
- The QuickShell panel is a modal overlay. It must stay above windows, ignore layer-shell exclusion, and remain vertically relaxed.
- Gemini detail views must preserve model-level quota and local usage rows where presenter data provides them.
- Overview cards render an equivalent compact summary for every provider: window providers show `5h X% / W Y%` from the five-hour and weekly lanes, and model-meter providers show their dominant model.
- Retained history must stay provider-shaped: model-meter providers keep per-model quota in `modelQuota`/`modelUsage` and never synthesize window lanes, and days with no quota sample and no local usage are omitted so the History view falls back to its empty state.
- Keep pace/reserve/hot detail in the modal/provider cards where it helps interpretation; keep it out of Waybar.

## Testing Guidelines
- Add regression tests under `test/` using the built-in Ruby test stack.
- Prefer testing normalization, selection logic, snapshot building, presenter output, and Waybar payloads without hitting live provider credentials.
- Treat live provider checks as smoke tests, not as the primary regression suite.
- `make syntax` must check each Ruby source file separately.
- Run `make test` before handoff and `make check` before release.
- Run `make check-live` only when the machine has working Codex, Claude, Gemini, OpenCode, and Z.ai credentials.

## Documentation Guidelines
- Keep `README.md`, `AGENTS.md`, `WIREFRAME.md`, and `docs/` aligned with the Ruby code.
- Do not describe retired upstream packaging, macOS runtime, Homebrew, Sparkle, WebKit, Swift, TypeScript, kitty, wofi, or unsupported providers as current surfaces.
- Do not call the project a port; use "independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete)" when attribution is needed.
- If a command or config key changes, update the README, CLI docs, runtime-contract docs, and wireframe in the same change.
- If install behavior changes, update `Makefile`, `docs/installation.md`, README install steps, and the wireframe install flow together.
- If runtime state changes, update `docs/runtime-contracts.md` and the QuickShell/Waybar descriptions together.

## Commit & PR Guidelines
- Use scoped, descriptive conventional commits.
- Keep commits atomic: docs, tests, UI behavior, install behavior, and provider logic should be separated unless tightly coupled.
- Include the validation commands you ran in handoff notes.
- Hard constraint: never edit `CHANGELOG.md` by hand. It is generated by `commit-and-tag-version`; release notes come from conventional commits, not manual edits.
- Release version bumps update `version.env` and the app-server client identity in `lib/codexbar/providers/codex.rb`; leave `CHANGELOG.md` to the release tooling.

## Agent Notes
- The top-level release truth is `README.md`, `AGENTS.md`, `WIREFRAME.md`, and `docs/`.
- Normal install must stay independent of SolverForge Linux desktop config.
- Use `make install-solverforge-linux-integration` for the explicit local SolverForge wrapper.
- Do not move provider fetching into Waybar.
- Do not make the checkout path part of the live desktop contract; install before renaming or moving this directory.
- After `make install`, restart `codexbar daemon` and the QuickShell panel before verifying anything on the live desktop: the install swaps the installed directory, so running processes keep executing the previous code and file watchers do not fire. See "Restart After Install" in `docs/installation.md`.
- `commit-and-tag-version` (v12.5.0) is installed globally. Run `commit-and-tag-version --release-as vX.Y.Z` directly; do not use `npx`.
- Publish releases to both remotes, `git.local` (Forgejo at `vigilance:3002`) and `blackopsrepl` (GitHub): push `main` and the release tag to each, then verify remote heads and zero divergence.
- `lib/codexbar/core/types.rb` metadata lines contain Nerd Font glyphs (non-ASCII private-use characters). Some editing tools silently strip them and blank the icons; after editing those lines, confirm every provider's `icon` still has its codepoint, or patch the file through Ruby with explicit codepoints.
