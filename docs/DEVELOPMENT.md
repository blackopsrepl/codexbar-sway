# Development Guide

## Product Shape

CodexBar is an independent Linux implementation inspired by [the original CodexBar](https://github.com/steipete/CodexBar) by [Steipete](https://github.com/steipete). It is built from:

- Ruby backend
- QuickShell panel
- Waybar JSON renderer
- cached runtime state in `~/.local/state/codexbar`

It is independent from the retired upstream desktop runtime.

## Local Checks

```bash
make syntax
make test
make smoke
```

Full preview release check:

```bash
make check
```

Stable live-provider check:

```bash
make check-live
```

## Source-Tree Runtime

```bash
bin/codexbar config validate
bin/codexbar waybar render
bin/codexbar ui status --format json --pretty
```

Direct QuickShell load:

```bash
make quickshell-load
```

The installed runtime lives under `~/.local/share/codexbar`. Use `make install && make configure-user` before relying on the app across checkout renames.

## Test Strategy

Prefer tests for:

- config normalization
- provider enabled/visible/overview/auto-selection semantics
- snapshot construction
- presenter output
- Waybar payload generation

Live provider checks are smoke tests, not the primary regression suite.
