# Cyclop

*English · [Русский](README.ru.md)*

The MacBook notch as a working tool. A native SwiftUI/AppKit app: invisible at
rest, and on hover it unfolds downwards into a panel with a player, a shelf for
files, clipboard history and your next meetings.

[![build](https://github.com/Carameil/cyclop/actions/workflows/build.yml/badge.svg)](https://github.com/Carameil/cyclop/actions/workflows/build.yml)

![The Cyclop panel](docs/panel.png)

## This fork

A personal fork of [akalikbergenov/cyclop](https://github.com/akalikbergenov/cyclop)
with a few additions for everyday backend work. Everything upstream is kept as is.

| Addition | What it does |
|---|---|
| **Tools tab** | Paste on the left, result on the right. Minified JSON comes out indented with keys in their original order; a column of ids comes out comma-separated; a unix timestamp comes out as a date, and a date as a timestamp. A click on the result copies it |
| **Hotkey** | `⌃⌥Space` opens the panel on the Tools tab wherever the pointer is, with the keyboard already taken. Esc on an empty field closes it. The combination is `hotkey` in `config.json`; empty turns it off. No Accessibility permission needed |
| **Clipboard search** | A filter above the history, for when forty rows is too many to scan |
| **Screenshot retention** | Settings → "Keep Only Today's Screenshots": everything older goes to the Trash at launch and at midnight. Off by default, as upstream. `screenshotRetentionDays` in `config.json` for any other window. The shelf also gets a "Trash Screenshots" button |
| **Volume** | A system volume slider next to the player controls on the Music tab. It drives the default output device and is not shown when that device's volume cannot be set |
| **Calendar by day** | The meeting list shows one day at a time: today first, arrows step through the week. Each occurrence of a recurring meeting is its own row |
| **Settings** | The per-tab switches in "Show in Panel" fold into a single "Tabs" row with an "N of M" counter |
| **Deploy with make** | `make install` builds the app and puts it into `/Applications`, `make update` pulls first — [Building](#building) |

The fork has no releases of its own: the images on the upstream releases page
are built without these additions. It is installed from source,
[here is how](#building). macOS 15 or newer.

```
0.0 % CPU at rest  ·  ≈40 MB + 14 MB helper  ·  3.7 MB bundle  ·  one permission, and only on a button
```

The track in the screenshot is playing in a browser tab — Cyclop reads it from
macOS itself, with no permissions and nothing to configure in the browser. How
that works is below.

## What it does

| Tab | What it does |
|---|---|
| **Music** | Artwork, track, artist, a scrubber that seeks, prev / play-pause / next. The source is **anything**: a player, a browser tab, any app macOS itself can see |
| **Shelf** | Drag files into the notch and they stay there until needed; drag a card out and the file goes wherever it is dropped. A click selects a card, ⌘-click selects several, and then the whole group is dragged. A screenshot taken to the clipboard is saved as a file and lands here too — including one taken on an iPhone, if you copy it there |
| **Clipboard** | The last 40 copies; a click puts an entry back on the clipboard |
| **Snippets** | A hand-kept list of what you are tired of retyping: an address, a phone number, an email. Added with a button in the panel, removed with the cross on a card; a click puts the text on the clipboard. The same list lives in `~/Library/Application Support/Cyclop/snippets.json` and can be edited there instead |
| **Calendar** | The next meeting a week ahead: how long until it starts and a button that joins the call — Zoom, Meet, Teams and others. The rest of the meetings as a list, one day at a time |
| **Translate** | Type on the left, the translation appears on the right — by itself, offline, using macOS's own facilities. English goes to Russian, Russian to English; the direction comes from the script the text is written in. macOS does not preinstall language packs, so the first time you have to download one: System Settings → General → Language & Region → "Translation Languages…" |
| **Currency** | An amount on one side, the other currency on the other; type into either. Rates are the one thing in Cyclop that comes over the network — a public table of daily rates, fetched once an hour, and only while the tab is on |
| **Teleprompter** | A script that scrolls under the camera at a speed you set. The notch is the one place on the screen a teleprompter belongs: reading happens right beside the lens, so on the recording the eyes stay on the camera instead of travelling to a window below it. The panel holds itself open while the text is moving — reading a script means not touching the trackpad |
| **Notes** | Scratch, on the right rail of icons: jot something down, come back, delete it or carry it off through the clipboard. Hovering lands with the caret ready; blank notes sweep themselves out |

The panel opens when the pointer reaches the notch and collapses when it leaves.
Tabs switch on hover as well — but only if the pointer has come to rest on the
icon: one passing through switches nothing. During a file drag the panel opens by
itself and goes straight to the shelf. The menu bar icon toggles the panel,
hides every tab's contents at once, and quits. The icon itself can be
removed — ⌘-drag it off the bar, or flip the switch in Settings — and
relaunching Cyclop brings it back.

Any tab can be switched off in **Settings → Show in Panel**. Off means two
things: the icon leaves the rail, and the tab's background work stops with
it — the clipboard poll, the calendar watch, the Now Playing helper, the
rate fetch. The rail is for what gets a glance between other things; a mode
used once a month may live there, but only as long as the people who never
use it can take it off.

## Requirements

- macOS 15 or newer (the Translate tab runs on Translation.framework)
- Swift 6 toolchain (the full Xcode is not needed, Command Line Tools are enough)
- `make` — ships with Command Line Tools

On macOS 27 with Command Line Tools only, the build switches to the 26.x SDK
installed alongside by itself (`Scripts/sdk.sh`): the plugin behind `@State`
in SDK 27 comes with Xcode alone. With the full Xcode nothing changes.

The app works on Macs without a notch too: the panel then treats a 180 × 24 pt
area at the top centre of the screen as one.

## Building

```bash
git clone https://github.com/Carameil/cyclop.git
cd cyclop
make install
```

| Command | What it does |
|---|---|
| `make build` | `Scripts/bundle.sh`: swift build, assembles `build/Cyclop.app`, ad-hoc signs it |
| `make install` | `make build`, then quits the running Cyclop, replaces `/Applications/Cyclop.app` and launches it |
| `make update` | `git pull --ff-only` on the current branch, then `make install`. Stops if the branch has diverged from its upstream |
| `make test` | `Scripts/test.sh`: `swift test`, with Command Line Tools as well |

To try a build without installing it: `make build && open build/Cyclop.app`.

The icon is generated in code, with no graphics editor involved:

```bash
swift Scripts/make-icon.swift "$PWD/Resources/AppIcon.icns"
```

## Installation

The fork is installed with `make install` and updated with `make update`, see
[Building](#building). The version is the first line of the menu bar menu.

A build from source is ad-hoc signed and is not notarised. On the Mac that
built it, it opens straight away; on any other Mac the first launch goes
through **System Settings → Privacy & Security → "Open Anyway"**.

Upstream images, `Cyclop-<version>.dmg` from the
[upstream releases page](https://github.com/akalikbergenov/cyclop/releases), are
signed with a Developer ID and notarised by Apple, so they open on the first
try — but without the fork's additions. Switching between such an image and a
local build changes the app's signature, and macOS may ask for the calendar
permission once more: that is what the permission is tied to.

### Building the image yourself

```bash
./Scripts/dmg.sh
```

Puts `build/Cyclop-<version>.dmg` next to the app, with an `/Applications`
shortcut inside. The version number comes from `Scripts/version`.

### Cutting a release

```bash
./Scripts/release.sh
```

Builds the image, tags `v<version>` and creates a GitHub release with the `.dmg`
attached. The notes are two parts: a few lines written by hand, kept in
`docs/releases/<version>.md`, followed by the commit list GitHub assembles. The
script refuses to run without the hand-written part — a list of commits answers
"what changed in the code", while whoever arrives is asking "what does this give
me", and no generator turns the first answer into the second.

The number is written in **one place**, `Scripts/version`. From there it goes
into the app's `Info.plist`, into the image name and into the tag, so they cannot
drift apart. The script also refuses to run on a dirty tree, on unpushed commits,
or when the tag already exists.

The image itself is built by `.github/workflows/release.yml` on the tag push, and
without Developer ID and notarisation secrets in the repository it refuses to
publish — see [docs/signing.md](docs/signing.md). Without them the fork is
deployed with `make install`.

## Permissions

**None** — until you open the calendar. The app asks for no Automation, no
Accessibility, no Screen Recording, and needs nothing configured in the browser.
The pointer position is read through `NSEvent.mouseLocation`, the clipboard
through the public `NSPasteboard`, Now Playing through a helper (see below).

Calendar access is the only permission Cyclop ever requests. It is needed by the
Calendar tab alone, and the system dialog appears neither at launch nor when the
tab is opened, but on an explicit press of a button on a screen that explains
why. Don't use the calendar and the app stays without permissions entirely.

A file put on the shelf from Downloads, Documents or the Desktop is the one thing
macOS asks about separately, and it asks when the shelf is opened, not at launch.
Refusing breaks nothing: the card stays, just without a preview.

Permissions would only be needed by the fallback path, if the main one ever stops
working: Automation for Apple Music and Spotify, and Accessibility for the media
keys.

## How it works

Why the window is shaped the way it is, why the pointer is polled on a
timer, why Now Playing lives inside `/usr/bin/perl`, what sitting idle
costs — eighteen notes on decisions the code does not show:
**[docs/architecture.md](docs/architecture.md)**.

## Limitations

- Now Playing rests on a private framework and on `/usr/bin/perl` remaining a
  platform binary without library validation. Apple can close this in any update
  — the Music and Spotify fallback takes over then. For the same reason the app
  is unfit for the App Store.
- Apple has deprecated the scripting runtimes (perl among them) and will remove
  them from the system one day. The helper survives exactly until that moment.
- The shelf references files rather than copying them: move the original and the
  card disappears on the next launch. The exception is clipboard screenshots,
  which are saved into `~/Pictures/Cyclop` and are never deleted automatically,
  even when the card leaves the shelf. Only the user clears that folder: the
  “Clear Screenshots Folder” in Settings sends its contents to the Trash —
  a hand too, not a schedule.
- Entries typed `org.nspasteboard.ConcealedType` (password managers) never enter
  the clipboard history.
- The join button appears only if the call link is in the event itself — in the
  location field, the notes or the URL. Meet, Zoom, Teams, Webex, Whereby, Jitsi,
  Telemost and Discord are recognised.
- A screenshot from the iPhone arrives through Universal Clipboard, so it needs
  what that needs: one Apple ID, Bluetooth and Wi-Fi on, Handoff enabled and the
  devices near each other. And it overwrites the clipboard on the Mac — what was
  overwritten stays in the Clipboard tab one click away.
- macOS does not preinstall translation languages — the first time, the pack has
  to be downloaded through System Settings; the panel says so and opens the right
  screen.

## Layout

```
Sources/Cyclop
├── main.swift                 entry point, .accessory
├── App/
│   ├── AppDelegate.swift      menu bar icon, launch at login
│   └── Strings.swift          string lookup, current language
├── Notch/
│   ├── NotchGeometry.swift    notch size and every rect derived from it
│   ├── NotchPanel.swift       the NSPanel above the menu bar
│   ├── NotchRootView.swift    panel hit-testing + drag & drop destination
│   ├── PointerWatcher.swift   pointer sampling: hover and click-through
│   ├── PanelState.swift       one display's share: open, dragged onto, typing
│   ├── NotchScreenPanel.swift the panel as it stands on one display
│   └── NotchController.swift  one model, one panel per display
├── Model/
│   ├── NotchViewModel.swift
│   └── PrivacyMode.swift      hiding contents: sections and reveals
├── Services/
│   ├── MediaController.swift  picks the Now Playing source
│   ├── NowPlayingFeed.swift   runs the helper in perl, parses its stdout
│   ├── PlayerBridge.swift     fallback: AppleScript + media keys
│   ├── ShelfStore.swift
│   ├── ClipboardStore.swift
│   ├── ScreenshotVault.swift  clipboard screenshots onto disk
│   ├── SnippetStore.swift     snippets: reading and writing snippets.json
│   ├── ConfigStore.swift      settings: reading and writing config.json
│   ├── Support.swift          ~/Library/Application Support/Cyclop
│   ├── DebouncedWrite.swift   writes to disk no more often than needed
│   ├── NoteStore.swift        scratch notes: notes.json
│   ├── Translator.swift       Translation.framework, direction by script
│   ├── CurrencyStore.swift    rates over the network, the one tab that has any
│   ├── TeleprompterStore.swift the script and where reading it has got to
│   ├── ScreenshotFolderWatcher.swift  screenshots saved to disk, onto the shelf
│   ├── CalendarStore.swift    EventKit: next meetings and the call link
│   ├── ToolsStore.swift       the Tools tab's text: what was pasted, what it became
│   ├── Normalizer.swift       JSON, id columns, unix time: the transformations
│   ├── HotkeyCenter.swift     global hotkey via Carbon, no Accessibility
│   └── SystemVolume.swift     CoreAudio: volume of the default output device
└── UI/                        NotchShape, tab panes, theme

Sources/CyclopMediaHelper
└── helper.m                   dylib for /usr/bin/perl: MediaRemote -> JSON
```
