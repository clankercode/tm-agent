# Release process

How to cut a release of `tm-agent`. Follow each gate in order. Do not invent
version numbers: read `info.toml` and confirm any bump with the human first.

## Prerequisites

- Clean working tree on the intended release branch (including untracked files)
- Trackmania + Openplanet available for the release-like compile gate
- `7z`, Python 3, `openplanet-lsp`, and optional `tm-remote-build`
- Compatible `mcp-tm`, `ai-api`, and `MLHook` dependencies installed

## 1. Version and changelog

Read the current version:

```bash
awk -F= '/^version/ { gsub(/[ \"]/, "", $2); print $2; exit }' info.toml
```

If the human approved a release version, update `info.toml` and move the
relevant `CHANGELOG.md` entries out of **Unreleased**. Commit those changes.

## 2. Mandatory release-like compile gate

Development and unit-test staging inject compile definitions. A public package
does not. Before tagging, stage and reload exactly that release-like shape:

```bash
./build.sh release-check
```

Pass criteria:

- Local dependencies stage and load successfully.
- `tm-agent` compiles and Openplanet reports `Loaded plugin 'tm-agent'`.
- The staged manifest has neither `DEV` nor `UNITTEST` definitions.
- No script exception appears after the successful load.

Restore day-to-day staging afterward with `./build.sh dev` if required.

## 3. Automated and live tests

```bash
openplanet-lsp check --plugins-dir "$HOME/OpenplanetNext/Plugins" \
  --plugins-dir .. --plugin-files-search-path src .
bash -n build.sh capture_ui.sh analyze_ui.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile capture_ui.py driver.py
./build.sh unittest
```

The unit-test gate is complete only when the fresh Openplanet log reports all
registered tests passed and no test failure. If Trackmania is available, also
run `./driver.py ping` and a representative agent/tool smoke.

## 4. Build and inspect the package

```bash
./build.sh release
VERSION="$(awk -F= '/^version/ { gsub(/[ \"]/, "", $2); print $2; exit }' info.toml)"
7z t "tm-agent-${VERSION}.op"
7z x -so "tm-agent-${VERSION}.op" info.toml
```

Require a non-empty archive, successful `7z t`, and an `info.toml` with the
approved version and no injected `DEV` or `UNITTEST` definition. Confirm that
`README.md`, `LICENSE`, `UNLICENSE`, and `CC0-1.0` are present too, so an
offline installer receives the same dual-license notice as the repository. The
`.op` is gitignored and is a release asset, not a source commit.

## 5. Push, tag, and publish

Only after the human asks to publish:

1. Push the release commit and wait for CI to pass.
2. Create an annotated `vX.Y.Z` tag on that commit and push it.
3. Draft hand-written notes from `CHANGELOG.md`; do not rely only on generated notes.
4. Create the GitHub release and attach `tm-agent-X.Y.Z.op`.
5. Download and integrity-test the published asset.

Example commands, after the version is confirmed:

```bash
VERSION="$(awk -F= '/^version/ { gsub(/[ \"]/, "", $2); print $2; exit }' info.toml)"
TAG="v${VERSION}"
git tag -a "$TAG" -m "tm-agent $VERSION"
git push origin master "$TAG"
gh release create "$TAG" --title "$TAG" \
  --notes-file /tmp/tm-agent-release-notes.md \
  "./tm-agent-${VERSION}.op"
```

Openplanet site publication is a separate human-controlled step.

## Quick checklist

```text
[ ] version confirmed; info.toml and CHANGELOG updated if needed
[ ] working tree clean (including untracked files)
[ ] ./build.sh release-check succeeds without DEV/UNITTEST
[ ] LSP, syntax checks, and fresh in-game unit tests pass
[ ] optional driver/tool smoke passes when the runtime endpoint is available
[ ] ./build.sh release and 7z t pass
[ ] packed info.toml has the approved version and no test/dev defines
[ ] packed README and all three dual-license files are present
[ ] release commit pushed and CI green
[ ] annotated tag and hand-written GitHub release created on human instruction
[ ] published .op downloaded and integrity-tested
```

## Do not

- Do not invent or silently bump a version.
- Do not tag when the release-like Openplanet compile gate fails.
- Do not commit `.op` artifacts.
- Do not publish or upload to Openplanet without explicit human direction.
