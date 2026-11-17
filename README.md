<p align="center">
  <img src="Support/AppIcon.iconset/icon_256x256.png" width="128" alt="unbox icon">
</p>

# unbox

**See what Box Drive keeps offline on your Mac – and free the space with one click.**

Box Drive lets you mark folders and files as *Available Offline*, but it never shows you a list of them.
unbox lives in the menu bar, lists everything that is marked offline together with the space it uses,
and lets you switch items back to online-only, removing the downloaded copies.

**[Download for Apple Silicon](https://github.com/emiterkamieni/unbox/releases/latest)**
 · [Releases](https://github.com/emiterkamieni/unbox/releases)
 · [Report an issue](https://github.com/emiterkamieni/unbox/issues)
 · [Polski](README.pl.md)

## Features

- **Everything that is offline, in one list.** Folders and files marked offline in Box Drive, grouped by
  top-level folder (for example per client), with the space each one uses on disk.
- **Make items online-only.** Uncheck them and click **Apply**. unbox runs Box Drive's own
  *Make Available Online Only* action and, optionally, removes the downloaded copies right away.
  Files stay visible in Finder and download again when opened.
- **Safe by design.** Files with changes that were not uploaded yet are never removed, and unbox never
  writes to Box Drive's files or downloads anything from the cloud itself.
- Sort by name or size, show items in Finder.
- **15 languages:** English, Polski, Deutsch, Français, Español, Italiano, Português, Nederlands, Svenska,
  Čeština, Українська, 日本語, 한국어, 简体中文 and 繁體中文. unbox follows the system language, or you
  can choose one in Settings.
- Launch at login.
- **Updates:** a notification when a new version is available (checked every 24 hours) and in-app
  installation with EdDSA-signed packages, powered by [Sparkle](https://sparkle-project.org).

## Requirements

- A Mac with Apple Silicon and macOS 13 Ventura or later (developed on macOS 26).
- [Box Drive](https://www.box.com/drive) in its File Provider mode – the default on current versions,
  with the Box folder in `~/Library/CloudStorage/Box-Box`.

## Install

1. Download `unbox-<version>-macos-arm64.zip` from the
   [latest release](https://github.com/emiterkamieni/unbox/releases/latest). To verify the download,
   put `SHA256SUMS` next to it and run `shasum -a 256 -c SHA256SUMS --ignore-missing`.
2. Unzip it and move `unbox.app` to `/Applications`.
3. Open unbox. The app is **ad-hoc signed, not notarized by Apple**, so macOS blocks the first launch.
   Open **System Settings → Privacy & Security**, click **Open Anyway** next to unbox and confirm.
   Do not disable Gatekeeper globally.
4. The unbox icon appears in the menu bar. Turn on **Launch at login** in Settings if you like.

Later versions install from inside the app.

## Using unbox

Click the menu bar icon to see the list. Each row shows the item, the folders above it and its size on
disk; hover over a row to show it in Finder.

1. Uncheck the items you no longer need offline. Their sizes turn orange – that is the space you get back.
2. Click **Apply**. unbox makes them online-only and removes the local copies.
3. A summary shows how much space was freed. Files that could not be removed (for example because they
   are open or still uploading) stay on disk and are listed in the summary.

You can still make items available offline with Box Drive in Finder; unbox picks them up automatically.

### Settings

| Setting | |
| --- | --- |
| Launch at login | Starts unbox when you log in. |
| Remove downloaded files after unchecking | On by default. When off, Box stops keeping the files offline but leaves the downloaded copies for Box or macOS to clean up later. |
| Refresh the list every | 1, 5, 15 or 30 minutes. The list also refreshes whenever you open it. |
| Language | System language or one of the 15 languages. |
| Notify about new versions | Checks GitHub for a new version once every 24 hours. |
| Check for Updates… | Checks right away and installs a new version on request. |

## How it works

- **Reading.** Box Drive stores its offline flags in `~/Library/Application Support/Box/Box/data/streemfs.db`.
  Box keeps the database locked, so unbox copies it together with its write-ahead log to a temporary folder
  and reads only the copy. Every result is confirmed with macOS File Provider. If Box changes its database
  format, unbox falls back to asking File Provider about each downloaded folder (slower).
- **Making items online-only.** unbox triggers Box Drive's own `UnmarkForOffline` File Provider action – the
  same action as *Make Available Online Only* in Finder. There is no public API for running another app's
  File Provider action, so this uses internal classes of the FileProvider framework, checked at runtime.
- **Freeing space.** The public `FileManager.evictUbiquitousItem` API, which is what *Remove Download* does in
  Finder. macOS refuses to evict files whose changes were not uploaded yet.
- unbox never writes to Box Drive's files and never downloads cloud files itself
  (`IOPOL_MATERIALIZE_DATALESS_FILES_OFF`).

### Privacy

unbox works entirely on your Mac. Its only network requests are update checks against this GitHub
repository – once a day when *Notify about new versions* is on, and when you click *Check for Updates…*.
No analytics, no accounts.

### Limitations

- A macOS update can change the internal FileProvider API. unbox then shows a notice and keeps listing your
  offline items; you make them online-only in Finder instead.
- A Box Drive update can change its database format; unbox then uses the slower fallback described above.
- Box Drive must be running to change offline settings.

unbox is an independent project and is not affiliated with or endorsed by Box, Inc.
Box and Box Drive are trademarks of Box, Inc.

## Building from source

Xcode is not required – the Command Line Tools are enough.

```sh
scripts/build.sh             # builds build/unbox.app and build/unbox-cli
scripts/build.sh --install   # also installs to /Applications and starts the app
```

The build downloads Sparkle 2.10.1 once (pinned by SHA-256) into `.build/`.

`build/unbox-cli` uses the same code from the command line:

```sh
build/unbox-cli list --sizes        # what is offline and how much space it uses
build/unbox-cli status <path>       # state of one item
build/unbox-cli unmark <path>       # make online-only and free the space (--keep-local to keep copies)
```

### Translations

Catalogs live in `Resources/Localizations/<language>.json`, keyed by the English text. English and Polish
are written next to the code (`L10n.text("English", "Polski")`). After changing interface text, run:

```sh
scripts/check-localization.py   # missing keys, placeholders and plural forms
```

### Icons

`swift scripts/make-icons.swift` regenerates the menu bar icon, the logo and the app icon in every size
(`Support/AppIcon.iconset`, `Support/AppIcon.icns`) from the SVG logo sources in `docs/`, which are not part
of this repository.

### Releases

```sh
scripts/release.py 1.0.1 2             # sets the version, builds, signs and writes dist/
git commit -am "Release 1.0.1"
scripts/release.py 1.0.1 2 --publish   # tags the commit and creates the GitHub release
```

Release notes are read from `release-notes/<version>.md`. The ZIP is signed with the Sparkle EdDSA key
(Keychain account `unbox-Releases`, or the exported key in `~/.config/unbox/sparkle_private_key`), and the
signature is checked against the app's `SUPublicEDKey` before anything is written. The app's update feed
is `https://github.com/emiterkamieni/unbox/releases/latest/download/appcast.xml`. Keep a backup of the private
key outside this repository – without it, existing installations cannot be updated.

## License

[GPL-3.0-only](LICENSE). unbox includes [Sparkle](https://github.com/sparkle-project/Sparkle), distributed
under the MIT license (`Contents/Resources/Sparkle-LICENSE` in the app).
