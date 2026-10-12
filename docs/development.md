# Development

The local loop: set up, build, run, regenerate. Shipping a build is [release.md](release.md);
verifying a change is [testing.md](testing.md).

## Requirements

- macOS 27 or later, on Apple silicon.
- Xcode 27 — it provides the SwiftUI macro plugin and the macOS 27 SDK.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), and for linting:
  `brew install swiftlint`.
- Node, for the generators and the local test stub servers `run-tests.sh` drives. It is the only
  scripting runtime here — building the app still needs none of it.

## First-time setup

Create the `Nanocast Self-Signed` code-signing identity once — builds sign with it, which is what keeps
macOS from forgetting the Accessibility grant on every rebuild. Follow **[signing.md](signing.md) §1**,
a few `openssl`/`security` commands.

That is the whole required setup. Editor configuration is personal and the repo does not prescribe it;
the section below is a note for anyone who wants it, not a step.

## Build & run

```sh
open Nanocast.xcodeproj    # then ⌘R
```

Or build the dev channel and restart it in one step, with [just](https://github.com/casey/just) (`brew install just`):

```sh
just dev
```

`just dev` builds to the fixed `build/DerivedData` path that keeps the TCC grants, quits a running `Nanocast Dev`, and opens the new build.

Or from the command line:

```sh
xcodebuild -project Nanocast.xcodeproj -scheme Nanocast -configuration Debug build
```

`xcodebuild` uses whatever `xcode-select` points at; if that's the Command Line Tools rather than
Xcode, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the SwiftUI
`@State`/`@FocusState` macros need Xcode's macOS platform).

`Nanocast.xcodeproj` is committed and generated from `project.yml` via XcodeGen — after changing
project settings in `project.yml`, run `xcodegen generate` and commit the result. There is no
`Package.swift`, and `Bundle.module` must never be used.

The app target builds and embeds `ClipboardTextHelper` and `FileIndexHelper` under `Contents/Helpers`,
signing each on copy. Build the app scheme to include them; copying only the main executable omits OCR
support and file indexing. Each helper's executable name is pinned in `project.yml`, so it never follows
the app's product name.

Dictation similarly embeds its Swift/Core ML helper, named `Nanocast Dev Dictation` in Debug and
`Nanocast Dictation` in Release, in an accessory `.app` bundle without a bundled icon. Model weights
download on demand; none are app resources.

### The dev channel

Debug builds are a separate channel: **`Nanocast Dev.app`**, bundle id `com.nanocast.app.dev`. Every
persisted thing is keyed by bundle id — `~/Library/Preferences/<id>.plist` (settings and hotkey
bindings), `~/Library/Application Support/<id>/` (the onboarding marker, Notes,
clipboard history, calculator history, launch ranking and frequent emoji; Notes unless a folder is
chosen),
`~/Library/Caches/<id>/` (exchange rates, the update check, staged downloads), the opt-in
`~/.config/nanocast-dev/settings.json` (`nanocast` on stable), the `SMAppService`
login item, and the Accessibility / Input Monitoring (TCC) grants — so a local build can neither read
nor clobber an installed app's state, and both run side by side.

**What earns a place in Caches is refetchable, and nothing else.** Anything the user would notice the
loss of goes in Application Support: `~/Library/Caches` is excluded from Time Machine and the system
reclaims it under disk pressure without saying so.

Consequences worth knowing:

- The dev build asks for Accessibility on its own the first time, and starts with **no** hotkeys bound
  and onboarding unseen. Grant and bind once; it persists across rebuilds, because the fixed build path
  and the `Nanocast Self-Signed` identity keep the TCC grant alive.
- Don't bind the same global hotkey in both — whichever registered first wins.
- The Hyper Key's Caps Lock remap lives on the keyboards, which are **shared, not per-bundle**:
  enable Hyper in one build at a time so their keyboard owners do not compete. An identical mapping
  already installed by another build is left unowned.

## Editor

Xcode works out of the box and needs nothing here. Everything below is optional, and which editor you
use is your business — the repo prescribes none of it.

VS Code gets code intelligence from SourceKit-LSP, which needs a `buildServer.json` because there is no
`Package.swift`. Build once, then hand the log to the sync script — that writes both `buildServer.json`
and the flag database:

```sh
brew install xcode-build-server
xcodebuild -project Nanocast.xcodeproj -scheme Nanocast -configuration Debug \
    -derivedDataPath build/DerivedData build 2>&1 | tee /tmp/nanocast-build.log
./Scripts/sync-lsp.sh /tmp/nanocast-build.log
```

Both files are git-ignored because they embed absolute paths, and `sourcekit-lsp` looks for
`buildServer.json` at the workspace root by name, so it cannot live in a subfolder. After this the
**Build Nanocast.app (debug)** task (⌘⇧B) and **F5** re-run the script on every build, so new and
renamed files keep resolving.

**Do not run `xcode-build-server config`.** It writes `kind: xcode`, and in that mode the server ignores
`.compile` entirely — it serves flags from a cache it scrapes out of `.xcactivitylog` instead. That
cache is only refreshed when `LogStoreManifest.plist` advances, and when the manifest stops updating
(it does) the editor silently pins itself to the source list from some older build: every reference to a
file added since reads _cannot find type X in scope_, in every file, until you restart the server. It
also mixes Release entries in with Debug and lets them win. `Scripts/sync-lsp.sh` keeps the mode
`manual`, where `.compile` is the single source of truth.

### Symbols in `Tests/`

`xcodebuild` never compiles the harnesses — they are not in the Xcode project — so nothing emits a
compile command for them, and without one an open harness reports every shipped type it uses as _cannot
find in scope_. Measured on `fuzz-test.swift`: 60 errors with no entry, 0 with one.

```sh
./Scripts/run-tests.sh --index    # merge the harness compile commands into .compile
```

It reads the source lists from `run-tests.sh` itself, so they cannot drift from what the suite actually
compiles. `Scripts/sync-lsp.sh` runs it too. Three things it has to get right, all of which fail
silently otherwise: every path is absolute, because `sourcekit-lsp` resolves the command itself and does
not apply `directory` to relative arguments; the command carries an explicit `-sdk`; and each entry
claims **only files under `Tests/`** — its harness plus any helper compiled beside it. The command
still lists every shipped source it compiles, so symbols resolve inside the harness, but claiming a
shipped source too would hand it this three-file command instead of the app's, and `.compile` is
last-wins.

A benchmark that stays out of the suite still needs flags, so `run-tests.sh` registers it as
`run index <name> <source...>`: `--index` emits its compile command and the runner never queues it.

Re-run it after adding a harness, then **Swift: Restart LSP Server** from the Command Palette — an
already-running server does not re-read `.compile`.

## Linting

```sh
./Scripts/lint.sh          # lint and check formatting for the whole project
./Scripts/lint.sh --fix    # auto-correct the mechanical subset and format, then lint
```

`lint.sh` runs three checks, and any failure blocks:

1. `swiftlint lint --strict`, so every [SwiftLint](https://github.com/realm/SwiftLint) violation is an error and no warning can pile up.
2. `./Scripts/format.sh --check`.
3. `node Scripts/check-settings-search.js`.

`.swiftlint.yml` excludes every `*.generated.swift` file and the two off-limits files in `DesignSystem/Scrolling/`. Its rules catch defects and leave layout to swift-format. The comment policy in [standards.md](standards.md#comments) is not among its rules. Three rule decisions are easy to undo by mistake:

- `empty_count` is disabled. `LauncherRankingRecord` and `PaletteRowIndex` have a `count` that is a hit count, not a collection count, so its `count == 0` to `isEmpty` rewrite does not compile on them.
- `optional_data_string_conversion` is disabled. Every `String(decoding:as:)` call site wants invalid UTF-8 repaired, and the suggested `String(bytes:encoding:)` returns nil instead.
- `force_try` is an error. An AX value is narrowed with `unsafeDowncast(_:to:)` after a `CFGetTypeID` check, because `as?` to a CF type does not compile and `as!` fails `force_cast`.

No CI runs this script, so run it locally before a change lands.

`lint.sh` also runs `check-localizations.js`, which fails on a string missing from any language, a
missing plural form, a stale entry, or a translation whose format specifiers differ from the source.

## Localization

```sh
./Scripts/sync-strings.sh   # build, merge new UI strings into Localizable.xcstrings, then check it
```

`xcodebuild` extracts strings but never writes them back to the catalog — only a build in Xcode's IDE
does — so run this after changing UI text, then translate what it added (Xcode's catalog editor, or
the JSON directly). A string whose source changed leaves its old entry stale; delete it. The rules for
writing localizable code are in [standards.md](standards.md#localization).

To see a language without changing the setting, launch the Debug build with
`-AppleLanguages '(de)'`; add `-NSDoubleLocalizedStrings YES` to find labels that truncate.

## Formatting

```sh
./Scripts/format.sh            # format Nanocast/ and Tests/ in place
./Scripts/format.sh --check    # report what would change, write nothing (exit 1 if any)
```

`swift-format` from the Xcode toolchain is the formatter. It is the same binary sourcekit-lsp formats with, so ⌘S in VS Code and this script cannot disagree. `.swift-format` at the repo root tunes it to this tree. Its `lineLength` of 130 matches SwiftLint's `line_length`, so code the formatter accepts never fails lint. Without the file, the stock configuration uses 2-space indent and rewrites every file.

Every `*.generated.swift` file is excluded: formatting one is hand-editing it, and the next
`node Scripts/gen-emoji.js` would revert it. swift-format also refuses any file that does not parse, so
a failure from either command is a syntax error rather than a tooling problem — and it is why ⌘S looks
like it does nothing while a file is mid-edit with unbalanced braces.
The two protected scrolling primitives, `EdgeDissolve.swift` and `ThinScrollbar.swift`, are also excluded.

## Generated data

Three Swift files are emitted by scripts and must never be hand-edited. Each downloads its source, so
run them online, then commit the result:

```sh
node Scripts/gen-emoji.js            # -> Nanocast/Features/Emoji/Model/EmojiData.generated.swift
                                     #    + Nanocast/Resources/EmojiKeywords/<language>.txt
node Scripts/gen-currencies.js       # -> Nanocast/Features/Calculator/Model/CurrencyData.generated.swift
node Scripts/gen-countries.js        # -> Nanocast/Features/Calculator/Model/CountryZoneData.generated.swift
```

`gen-emoji.js` also writes one CLDR keyword pack per language in its `KEYWORD_LOCALES`; adding a
language is one line there. Pass a directory to keep the downloads between runs:
`node Scripts/gen-emoji.js /tmp/emoji-sources`.

`gen-countries.js` joins IANA's `zone.tab` with CLDR's `en` territory names on the ISO 3166 code. Re-run
it when IANA adds or moves a country's zone; see [calculator.md](features/calculator.md#time-zones).

`gen-currencies.js` joins three sources on the ISO code: the **fiat rate feed**'s own quote list — the
same feed `CurrencyRateStore` fetches rates from, so the table and the rate source cannot drift apart
— **Unicode CLDR**'s `en` currency data, which supplies display names, signs and the singular/plural
noun, and **CLDR's supplemental currency data**, which says which codes are still spent anywhere. That
last one is not optional: the feed carries no retirement metadata and quotes codes their countries
abandoned years ago. Both CLDR files are read from the pinned `cldr-json` checkout rather than the
host's `Intl`, whose output shifts with the local ICU version and would make the file unreproducible.

Only unambiguous data is emitted. Anything two currencies claim — `dollars`, `pounds`, `krona` — is
left out and decided by hand in `CalcCurrency.contested`. The crypto tickers aren't generated at all:
they have no external source of truth, so `CalcCurrency.crypto` is hand-written, and that same list is
the set of symbols the fetch asks for. Re-run the script when a currency is added or retired; nothing
breaks in the meantime, since an unquoted code just reports "no exchange rate".

## Sync with upstream Tinycast

`main` is an untouched copy of upstream Tinycast. Your work lives on `polo`, on top of a snapshot commit named `Rename upstream <sha> to Nanocast`. That commit is `main` after `Scripts/rename-upstream.sh` renamed every Tinycast name, path and bundle id to Nanocast.

To take new upstream changes:

1. Sync `main` with upstream, for example with **Sync fork** on GitHub. Never commit to `main`.
2. Run `./Scripts/sync-upstream.sh` on `polo`. It renames the new `main` into a fresh snapshot and rebases your commits from the old snapshot onto it.
3. Run `./Scripts/run-tests.sh`, then `git push --force-with-lease`.

To have an agent run the sync, resolve the conflicts and drop upstream changes to removed features, run `/skill:syncing-upstream`. It stops before the push so you can review.

The rename runs on both sides, so only real upstream changes can conflict. The script turns on `git rerere`, so a conflict you resolved once resolves itself next time. If `Nanocast.xcodeproj` conflicts, regenerate it with `xcodegen generate` and do not resolve it by hand.

If a rebase step stops on conflicts, run `./Scripts/port-upstream.sh <sha>...` with the upstream commits you keep. It deletes the paths your commits deleted, takes your version of every other conflicted file, and merges each kept commit's renamed change into it. It stages every file that merged cleanly and prints the files that still hold conflict markers.

Links to `abue-ammar/tinycast` keep pointing upstream. Fork identity lives in `.github/workflows/release.yml`, `Scripts/release-notes.sh`, `ReleaseFeed.repository`, the About window links, `README.md`, `LICENSE` and `NOTICE.md`.
