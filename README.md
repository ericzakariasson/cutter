# Cutter

A macOS menu bar app that moves and resizes the focused window with global keyboard shortcuts.

![Animation of Cutter's default shortcuts. On two displays, one above the other, a window takes the left half of the lower display with ⌃⌥←, the right half with ⌃⌥→ and the whole visible area with ⌃⌥↩, then moves to the display above with ⌃⌥↑ and back down with ⌃⌥↓.](docs/demo.gif)

The animation is drawn by `./scripts/make-demo.sh` from the app's own placement code and default shortcuts.

| Action | Default shortcut |
| --- | --- |
| Maximize (fills the screen below the menu bar and above the Dock; not native full screen) | ⌃⌥↩ |
| Left Half | ⌃⌥← |
| Right Half | ⌃⌥→ |
| Move to Previous Display | ⌃⌥↑ |
| Move to Next Display | ⌃⌥↓ |
| Top Half, Bottom Half | none |
| Top Left, Top Right, Bottom Left, Bottom Right | none |
| Toggle Full Screen (native) | none |

Every shortcut can be changed or removed in the settings window. With several displays, a placement applies to the display the window is on.

macOS draws the shortcut glyphs in Cutter's menu, and on macOS 26 it draws arrow keys as filled triangles, so the menu shows ⌃⌥◀ where Settings shows ⌃⌥←.

## Install

Cutter runs on macOS 13 or later, on Apple silicon and Intel Macs.

1. Download `Cutter-<version>.dmg` from the [latest release](https://github.com/ericzakariasson/cutter/releases/latest).
2. Open the DMG and drag Cutter onto the Applications shortcut next to it. Eject the DMG.
3. Open Cutter from Applications. Cutter is not notarized by Apple, so macOS stops it the first time. A dialog titled "“Cutter” Not Opened" says "Apple could not verify “Cutter” is free of malware that may harm your Mac or compromise your privacy." Click **Done**.
4. Open System Settings > Privacy & Security and scroll down to Security. Next to "“Cutter” was blocked to protect your Mac." click **Open Anyway**. Confirm with **Open Anyway** in the dialog that asks "Open “Cutter”?", then enter your password or use Touch ID.
5. Cutter starts: its icon appears in the menu bar and its settings window opens. Click **Open Accessibility Settings…** and turn on Cutter in the list. The shortcuts work from that moment, without a relaunch.

Things to know:

- The wording in steps 3 and 4 is that of macOS 26. Earlier versions word the first dialog differently; **Open Anyway** is in the same place.
- **Open Anyway** is offered for about an hour after macOS stopped the app. If it is gone, open Cutter again and go back to Privacy & Security.
- Start Cutter from Applications, not from inside the DMG, or launch at login will not find it later.
- To update, quit Cutter, replace it in Applications with the one from the new DMG, and repeat steps 3 and 4: macOS asks once for every download. Accessibility access carries over from one release to the next (see [Signing](#signing)).
- To remove Cutter, quit it and move it to the Trash. Its entries under Privacy & Security > Accessibility and General > Login Items can be removed there.

## Moving between displays

Move to Previous Display and Move to Next Display send the focused window to another display. Pressing one repeatedly cycles through all displays and wraps around at the ends; with one display they do nothing.

- **Order.** The displays are ordered as they are arranged in System Settings > Displays: rows from top to bottom, and left to right within a row. With one display above another, ⌃⌥↑ goes to the upper one and ⌃⌥↓ to the lower one. With displays side by side, ⌃⌥↑ goes left and ⌃⌥↓ goes right. With two displays, either shortcut swaps.
- **Size and position.** The window keeps its place within the visible area: a maximized window stays maximized, a left half stays a left half, and any other window covers the same fraction of the new display at the same relative position, so it grows or shrinks with the display. It always ends up fully inside the visible area.

## Shortcuts and other apps

A shortcut belongs to Cutter while Cutter runs: the frontmost app no longer receives it. Control+Option with Return or an arrow is free in macOS and in most apps, with two exceptions worth knowing:

- VoiceOver uses Control+Option as its modifier, and Control+Option+arrows move its cursor. If you use VoiceOver, pick other shortcuts.
- Rectangle and Magnet use the same combinations by default. Run only one of them with these shortcuts.

macOS does not tell an app that another app has registered the same shortcut, so Cutter cannot warn about such a clash. If a shortcut does nothing or does the wrong thing, look for another app using it.

The recorder asks before it accepts a shortcut that already means something everywhere, such as ⌘Q, ⌘C, ⌘V, ⌘W or ⌘↩: press it a second time to use it anyway.

## Build

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```sh
./scripts/build-app.sh
open build/Cutter.app
```

Run the tests with `./scripts/test.sh`.

### Making a release

1. Once, on the Mac that makes the releases: `./scripts/setup-release-key.sh` creates the release key and asks for a passphrase to lock it with. Commit `Support/release-certificate.txt`, which it updates. Back up the folder it names and keep the passphrase; neither can be recovered.
2. Set the version: `CFBundleShortVersionString` in `Support/Info.plist`. The app and the DMG's name both take it from there.
3. `./scripts/make-dmg.sh` builds the app for Apple silicon and Intel, asks for the passphrase, signs, and writes `dist/Cutter-<version>.dmg`. It prints the DMG's size and SHA-256.
4. On GitHub, create a release with the tag `v<version>`, attach the DMG, and put the SHA-256 in the notes.

`make-dmg.sh` needs only the Command Line Tools and opens nothing on screen. `CUTTER_SIGNING=adhoc ./scripts/make-dmg.sh` makes a DMG to try out without the release key; its name ends in `-adhoc` and it is not for publishing. `./scripts/test-dmg.sh` checks both scripts with a throwaway key.

## First run

Cutter needs Accessibility access to move other apps' windows. On first launch it opens its settings window and explains this. Click **Open Accessibility Settings…**, turn on Cutter in the list, and the shortcuts start working without a relaunch. Until then Cutter registers no shortcuts, so it does not swallow key presses it cannot act on.

Cutter has no Dock icon. Open its settings from the menu bar icon, or by opening the app again while it runs.

## Signing

macOS ties the Accessibility permission to the app's code signature. So that the permission survives rebuilds, `build-app.sh` signs every build with the same self-signed certificate. It creates the certificate on the first build, in a keychain of its own under `~/Library/Application Support/Cutter/signing`. Your login keychain and keychain search list are not touched.

**This weakens the Accessibility permission, and you should know how.** The signing keychain's password is written in `scripts/signing.env` and the keychain never locks. Any process running as you can therefore sign a program of its choice as Cutter. macOS then treats that program as Cutter, so it has Cutter's Accessibility access without asking you: it can read and control every app's windows and send them input. Without the certificate, such a process would have to get you to grant it access itself. The certificate gives nothing to an attacker who cannot already run code as you.

That key is for your own builds. Releases are signed with another one; see below.

- To avoid the trade-off, build with `CUTTER_SIGNING=adhoc ./scripts/build-app.sh` and delete the signing folder. Access must then be granted again after every build.
- To remove the certificate, delete that folder. The next build creates a new one, and macOS will ask for Accessibility access again.
- If Cutter is switched on under Accessibility but still says it needs access, the entry belongs to an older signature. Remove it with `tccutil reset Accessibility com.ericzakariasson.Cutter` and grant access again.

### Releases

The DMGs on the Releases page are signed with a separate release key, and are not notarized by Apple.

- **Why one key for all releases.** Access you give one release carries over to the next only when both are signed with the same key. A release signed without a key, or with a new one, shows up as switched on under Accessibility and still has no access.
- **What the key is worth.** Whoever holds the release key can make a program that macOS treats as Cutter. On a Mac where Cutter has Accessibility access, that program has it too, without asking. If you install a release, you are trusting the maintainer to keep that key safe.
- **How it is kept.** Unlike the build key, the release key is in a keychain locked with a passphrase that is not in this repository and not stored on the Mac. `make-dmg.sh` asks for it, signs, and locks the keychain again. A copy of the keychain file is useless without the passphrase.
- **Checking a download.** The SHA-1 of the release certificate is in `Support/release-certificate.txt`. `codesign --display --requirements - /Applications/Cutter.app` prints the certificate a copy of Cutter was signed with.

## Troubleshooting

```sh
build/Cutter.app/Contents/MacOS/Cutter --diagnose
```

prints the screens Cutter sees and the configured shortcuts. It only reads, so it is safe while Cutter is running. Run from a terminal, its "Accessibility access" line reports the terminal's permission, not Cutter's.

```sh
open -n build/Cutter.app --stdout /tmp/cutter-self-test.log --args --self-test
cat /tmp/cutter-self-test.log
```

checks placement end to end once Cutter has Accessibility access. On each screen it opens a small window of its own, applies every placement to it and reports where the window ended up. It then makes that window's app stop responding and checks that Cutter gives up on it within about a second, and with several screens it sends a window once around all of them. It moves no other window. A screen showing a full-screen app is skipped for the placements, because a new window cannot open there.

To try a build while the copy in `build/` is running, put it elsewhere with `CUTTER_APP_DIR=<dir> ./scripts/build-app.sh`. Add `CUTTER_BUNDLE_ID=<another id>` for a copy with settings of its own that can run next to the real one; it has no Accessibility access until you grant it.

## Adding a placement

Add a case to `WindowAction` in `Sources/CutterCore/WindowAction.swift` with a title and the fraction of the screen it covers, and give it an icon in `Sources/Cutter/SettingsView.swift`. The compiler points at both places. The settings window, the menu and shortcut storage pick the new action up on their own.

## Layout

- `Sources/CutterCore`: actions, frame math, the shortcut model and its storage. No AppKit; covered by unit tests.
- `Sources/Cutter`: the app. Global shortcuts (`HotKeyCenter`), window control through the Accessibility API (`WindowManager`), the permission flow, the menu and the settings window.
- `Sources/CutterDemo`: draws the animation above, `docs/demo.gif`, off-screen. Run `./scripts/make-demo.sh` to regenerate it after changing the placements or the default shortcuts; add `--mp4 <file>` for an H.264 movie as well.
- `scripts`: building, signing, packaging and testing. `make-dmg.sh` makes the DMG for a release. `make-icon.swift` draws `Support/AppIcon.icns`.

## Known limits

- A window in native full screen ignores placements and display moves; leave full screen first.
- A display that is showing a full-screen app has no desktop for another window to land on, so a window sent there may not appear.
- An app that has stopped responding cannot be moved. Cutter waits about a second for it and then beeps.
- Some windows refuse a size (minimum sizes, fixed-size dialogs, terminals that resize in whole characters). Cutter then keeps the window against the screen edges the placement touches.
- `build-app.sh` builds for this Mac's architecture only. `make-dmg.sh` builds for Apple silicon and Intel.
