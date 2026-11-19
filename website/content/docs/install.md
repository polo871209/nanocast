---
title: Install
description: Homebrew, release channels, direct downloads, and updates.
---

Nanocast needs an Apple silicon Mac with **macOS 26 or later**.

## Homebrew

Homebrew is the easiest way to install Nanocast.

```bash
brew install --cask nanocast
```

### Channels

Each channel is a **separate app** with its own settings, permissions and login item. They can run
side by side, so you can keep the stable version and try a beta at the same time.

| Channel | Cask            | App                 |
| ------- | --------------- | ------------------- |
| Stable  | `nanocast`      | `Nanocast.app`      |
| Beta    | `nanocast@beta` | `Nanocast Beta.app` |

```bash
brew install --cask nanocast@beta
```

The beta doesn't share settings with the stable version. To move your setup over, use
[Backup](/docs/reference/backup).

## Downloading directly

Builds are also on the [Releases page](https://github.com/abue-ammar/tinycast/releases).

Open the DMG and drag Nanocast to Applications. Every release is signed with Nanocast's Apple
Developer ID and notarized by Apple, so macOS opens it without a warning.

## Updating

Nanocast updates itself. Once a day it checks for a new release on its own channel. When there is
one, a window shows what changed. **Update Now** downloads and installs it, and **Relaunch** starts
the new version. You can also check at any time with **Check for Updates** in the launcher, the menu
bar or **Settings → About**.

To stop the daily check, turn off **Automatically check for updates** in **Settings → General**.
Checking by hand still works.

Because the app manages its own updates, `brew upgrade` skips Nanocast. This is expected. See
[Updates](/docs/reference/updates) for details.

Every release is signed with the same certificate, so your Accessibility permission keeps working
after an update.

## Uninstalling

```bash
brew uninstall --cask nanocast
```

To also remove the files Nanocast created, add `--zap`:

```bash
brew uninstall --zap --cask nanocast
```

That deletes your snippets, notes, quicklinks, clipboard history and AI chats too, so copy out
anything you want to keep first. For the beta, use `nanocast@beta`.

API keys you saved for AI providers or MCP servers, and extension sign-ins, are stored in your login
Keychain. Remove them in Keychain Access if you want them gone too.

To remove a _different_ app and the files it left behind, use Nanocast's
[built-in uninstaller](/docs/launcher/uninstall).
