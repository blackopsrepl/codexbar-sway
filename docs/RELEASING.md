# Release Process

This repo releases as a Linux-first Ruby + QuickShell + Waybar source/user-prefix package.

It does not define a native desktop bundle, updater feed, tap/cask package, or notarization flow.

## Release Tracks

- Preview release: `make check` passes.
- Stable release: `make check-live` passes on the intended release machine with live Codex, Claude, and Gemini credentials.

## Required Gates

Before tagging:

```bash
make syntax
make test
make smoke
make check
```

For stable:

```bash
make check-live
```

Install and rename-safety validation:

```bash
make install
make configure-user
make install-solverforge-linux-integration
readlink -f ~/.local/bin/codexbar
codexbar config validate
codexbar waybar render
codexbar ui status --format json --pretty
rg "<old checkout directory name>" ~/.codexbar ~/.local/bin ~/.local/share/solverforge
```

The final `rg` command must have no live integration hits. Use the actual old checkout directory name when running it.

## Documentation Gate

Release-facing docs must describe the current Linux product only:

```bash
rg "<retired product term pattern>" README.md AGENTS.md WIREFRAME.md docs
```

Any hit for retired upstream product, packaging, or provider claims must be removed from current docs.

## Provider Claims

The release may claim support for exactly:

- `codex`
- `claude`
- `gemini`

Provider behavior must match `lib/codexbar/providers/*`.

## Tagging

When validation passes and release notes are final:

```bash
git tag -a v0.1.1 -m "CodexBar 0.1.1"
git push origin main --tags
```

Adjust the remote command to the actual configured release remote.
