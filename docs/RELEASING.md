# Release Process

This repo releases as a Linux-first Ruby + QuickShell + Waybar source/user-prefix package.

It does not define a native desktop bundle, updater feed, tap/cask package, or notarization flow.

## Release Tracks

- Preview release: `make check` passes.
- Stable release: `make check-live` passes on the intended release machine with live Codex, Claude, Gemini, OpenCode, and Z.ai credentials.

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
- `opencode`
- `zai`

Provider behavior must match `lib/codexbar/providers/*`.

## Release Workflow

1. Commit the release work as atomic conventional commits (`feat`, `fix`, `docs`, ...). The changelog and version bump are derived from these commits.
2. Run the required gates on the exact tree being released.
3. Cut the release with the globally installed release tool. Do not use `npx`, do not hand-edit `CHANGELOG.md`, and never create the release commit or tag by hand:

   ```bash
   commit-and-tag-version --release-as vX.Y.Z
   ```

   The tool bumps `version.env` and the Codex app-server client identity in `lib/codexbar/providers/codex.rb`, regenerates `CHANGELOG.md`, creates the release commit, and tags it.

4. Verify the release before publishing:

   ```bash
   git show --stat --oneline HEAD   # exactly version.env + codex.rb + CHANGELOG.md
   git tag --points-at HEAD         # the intended tag
   git status --short               # must be clean
   sed -n '1,16p' CHANGELOG.md      # correct heading and compare URL
   ```

5. Deploy the released version and restart the runtime — running processes keep executing the previous code until restarted (see "Restart After Install" in `docs/installation.md`):

   ```bash
   make install
   # restart codexbar daemon, then restart the panel and run: codexbar ui open
   ```

6. Publish to both remotes and prove the remote state:

   ```bash
   git push git.local main vX.Y.Z
   git push blackopsrepl main vX.Y.Z
   git fetch git.local main blackopsrepl main
   git rev-list --left-right --count git.local/main...main     # expect: 0 0
   git rev-list --left-right --count blackopsrepl/main...main  # expect: 0 0
   git ls-remote git.local refs/tags/vX.Y.Z
   git ls-remote blackopsrepl refs/tags/vX.Y.Z
   ```

Both remote tag SHAs must match the local tag object, and divergence must be `0 0` on `main` for every remote.
