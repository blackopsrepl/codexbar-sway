# Changelog

## 0.1.0 - Unreleased

### Added
- Linux-first Ruby backend for CodexBar.
- QuickShell panel as the only human-facing UI.
- Waybar JSON renderer for the compact bar chip.
- Cached daemon state in `~/.local/state/codexbar`.
- Provider support for `codex`, `claude`, and `gemini`.
- Deterministic `make install` user-prefix installation under `~/.local/share/codexbar`.
- User config alignment through `make configure-user`.
- Explicit SolverForge Linux Waybar wrapper installation through `make install-solverforge-linux-integration`.
- Release validation through `make check` and live-provider validation through `make check-live`.

### Removed
- Upstream macOS/AppKit/Sparkle/Homebrew release documentation from the current release surface.
- Unsupported upstream provider documentation from the current Linux release docs.
- `PRD.md` as a release authority.
