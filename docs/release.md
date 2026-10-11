# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/Nanocast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/Nanocast-0.5.7.dmg
```

It builds a Release `Nanocast.app` signed with `Nanocast Self-Signed` and packs it with an
`/Applications` symlink. Official releases are built by CI, below.

## Signing & Gatekeeper

Both local builds and CI releases sign with the same stable `Nanocast Self-Signed` identity, not an
Apple Developer ID — so macOS quarantines a directly-downloaded DMG. The Homebrew cask strips that
automatically; direct downloaders run `xattr -dr com.apple.quarantine /Applications/Nanocast.app` once.
Full details in [signing.md](signing.md).

## How the in-app updater consumes a release

Every release publishes two assets from one build: `Nanocast-<version>.dmg`, which people download by
hand and which the cask installs, and `Nanocast-<version>.zip`, which the in-app updater installs. The
zip is produced with `ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the code
signature verifiable, which matters because the updater refuses any bundle whose signature does not
prove it is ours.

Three things a release must keep true, or the updater skips it:

- **It carries a `.zip` asset.** A DMG-only release is not installable and is not offered.
- **The tag parses as `vMAJOR.MINOR.PATCH-REVISION` and the release is not a prerelease.** A tag of any other shape is skipped.
- **It is not a draft.**

**The cask declares `auto_updates true`.** That is Homebrew's flag for an app that manages its own
version, and it is what keeps `brew update && brew upgrade` from fighting an app that updated itself:
brew never reports Nanocast outdated, never re-downloads it, and never rolls a self-updated copy back.
Removing that line would reintroduce exactly those three problems. See
[features/updates.md](features/updates.md).

## Checks before a merge

The whole bar in [testing.md](testing.md#definition-of-done) runs locally before a change lands on the default branch. The one CI check is `.github/workflows/cask.yml`, which runs `brew style` and `brew audit --cask --strict` when a pull request or push touches `Casks/`.

## Releasing

`.github/workflows/release.yml` builds and publishes a release from GitHub Actions, no local machine needed. Run it from the **Actions** tab (`Release` → **Run workflow**). It takes no input, because the version comes from Tinycast.

The version is `<tinycast>-<revision>`, for example `0.11.21-1`. Nanocast has no version line of its own:

1. The job finds the `Rename upstream <sha> to Nanocast` snapshot and fetches the Tinycast tags into `refs/tags/tinycast/`.
2. `<tinycast>` is the nearest Tinycast tag below the snapshot, without its channel suffix. `v0.11.21-beta.120` gives `0.11.21`.
3. `<revision>` is one more than the highest `v<tinycast>-N` tag on `origin`, and starts at `1` after each upstream sync that moves the base.

It builds `Nanocast.app` (`com.nanocast.app`) on the `xcode-27` runner image with Xcode 27 and publishes a GitHub Release tagged `v<version>` with a versioned DMG and zip asset. A second job then points the Homebrew cask at that release, below.

The floor is macOS 27, which boots only on Apple silicon, so `ARCHS_STANDARD` is `arm64` alone and no Intel build exists. The job asserts `arm64` alone and a `27.0` floor on every shipping binary: the app, `ClipboardTextHelper`, `FileIndexHelper` and `Nanocast Dictation`. A helper built with a different floor or slice fails only when clipboard OCR, file indexing or dictation runs, so the check covers all four.

The Dictation helper derives its own identifier from `NANOCAST_BUNDLE_IDENTIFIER` with a `.dictation` suffix; signature verification checks that its bundle and signing identifiers agree and remain distinct from the main app.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
TAG=v0.9.13 ./Scripts/release-notes.sh /tmp/body.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its author and number since the previous non-draft release — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and without Conventional Commits. The tag is created server-side by `gh release create`.

**The body is split by `<!-- nanocast:install -->`.** Everything above it is the changelog; everything below is the Homebrew and quarantine text, which only a download page needs. The update window cuts at that marker — see [features/updates.md](features/updates.md). Full PR URLs are shortened to `#304`, which still autolinks on the web and fits a 460pt window.

### Homebrew cask

This repository is its own Homebrew tap. `Casks/nanocast.rb` installs the DMG of the release that its `version` and `sha256` name. Because the repository is not named `homebrew-nanocast`, users tap it by URL:

```sh
brew tap polo871209/nanocast https://github.com/polo871209/nanocast
brew trust --tap polo871209/nanocast
brew install --cask polo871209/nanocast/nanocast
```

The `cask` job in `release.yml` runs on `macos-latest` after the release is published. It does these steps in order:

1. Checks out the default branch and writes the new `version` and the DMG `sha256` into `Casks/nanocast.rb`. The `sed` is anchored to `^  version` and `^  sha256`, so the two-space indent on those lines is load-bearing.
2. Links the checkout as the tap with `Scripts/link-tap.sh`, then runs `brew style`, `brew audit --cask --strict --online` and `brew fetch --cask`. The fetch downloads the published DMG and fails if its checksum differs.
3. Commits `nanocast <version>` as `github-actions[bot]` and pushes to the default branch with `GITHUB_TOKEN`. If the push is rejected because the branch moved, it rebases and tries again, three times at most.

That bump commit is the only commit CI makes. It needs no extra secret, but a branch rule that blocks direct pushes from `github-actions[bot]` makes step 3 fail. The release itself stays published.

The cask removes the quarantine flag in `postflight_steps`, because the app is self-signed and Gatekeeper refuses a quarantined copy. Homebrew 7 runs those steps in a sandbox that can write to the Applications folder.

To check a cask change locally, link this checkout as the tap and run the same commands as CI:

```sh
./Scripts/link-tap.sh
brew style Casks/
brew audit --cask --strict polo871209/nanocast/nanocast
```

`Scripts/link-tap.sh` refuses to run if `polo871209/nanocast` is already tapped from GitHub. Remove that tap with `brew untap polo871209/nanocast` first.
