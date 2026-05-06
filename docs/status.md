# Status

CodexBar does not run a separate provider-status polling system in the current Linux release.

Provider health is derived from fetch results:

- successful usage payloads render healthy, warning, critical, or pace classes through the presenter
- provider fetch errors are preserved in snapshots and surfaced through UI/Waybar output
- stale snapshots are detected from `generatedAt` and `runtime.refreshSeconds`

See `docs/runtime-contracts.md` for the snapshot and Waybar payload shape.
