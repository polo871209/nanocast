# Nanocast

**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <a href="https://github.com/polo871209/nanocast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/polo871209/nanocast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 27 or later"
       src="https://img.shields.io/badge/macOS-27%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry.

Nanocast is my personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar.

<p align="center">
  <img src="docs/screenshot.png" alt="Nanocast command palette" width="720">
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — find files and folders by name in a private index of the folders you choose,
  kept current as files change. It needs Full Disk Access.
- **Dictionary** — look a word up with the Define Word command, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **Screenshot** — freeze the screen, pick a window or a pixel-exact area with a loupe, mark it up with shapes, a highlighter, text, numbered steps and mosaic, then copy, save or pin it. A scrolling capture scrolls a long page by itself, stitches it into one image and opens it in the editor.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

Nanocast needs macOS 27 or later, which runs only on Apple silicon. This repository is its own Homebrew tap:

```sh
brew tap polo871209/nanocast https://github.com/polo871209/nanocast
brew trust --tap polo871209/nanocast   # required for third-party taps
brew install --cask polo871209/nanocast/nanocast
```

Homebrew clears the macOS quarantine flag on every install and update, so there is nothing else to
run. Downloading a DMG from [Releases](https://github.com/polo871209/nanocast/releases) instead?
Nanocast is self-signed, so clear the flag once:
`xattr -dr com.apple.quarantine "/Applications/Nanocast.app"`.

## Permissions

**Accessibility** — needed when Nanocast pastes clipboard items or dictated text into another app or scrolls a page for a scrolling capture.
You're prompted when you first use a feature that needs it; grant access in **System Settings →
Privacy & Security → Accessibility**.

**Screen Recording** — needed by Capture Screenshot and the window switcher's previews. Nanocast asks the first time you capture. Grant access in **System Settings → Privacy & Security → Screen & System Audio Recording**.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Nanocast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging and release
workflows. **[docs/](docs/README.md)** indexes everything else — architecture, engineering
standards, the design system and one document per feature.

## License

[AGPL-3.0](LICENSE)
