# Cutter

A macOS menu bar app that moves and resizes the focused window with global keyboard shortcuts.

| Action | Default shortcut |
| --- | --- |
| Maximize (fills the screen below the menu bar and above the Dock; not native full screen) | ⌃⌥↩ |
| Left Half | ⌃⌥← |
| Right Half | ⌃⌥→ |
| Top Half | ⌃⌥↑ |
| Bottom Half | ⌃⌥↓ |
| Top Left, Top Right, Bottom Left, Bottom Right | none |
| Toggle Full Screen (native) | none |

Every shortcut can be changed or removed in the settings window. With several displays, an action applies to the display the window is on.

A shortcut belongs to Cutter while Cutter runs: the frontmost app no longer receives it. Control+Option with Return or an arrow is free in macOS and in most apps, with two exceptions worth knowing:

- VoiceOver uses Control+Option as its modifier, and Control+Option+arrows move its cursor. If you use VoiceOver, pick other shortcuts.
- Rectangle and Magnet use the same combinations by default. Run only one of them with these shortcuts.

## Build

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```sh
./scripts/build-app.sh
open build/Cutter.app
```

Run the tests with `./scripts/test.sh`.

## First run

Cutter needs Accessibility access to move other apps' windows. On first launch it opens its settings window and explains this. Click **Open Accessibility Settings…**, turn on Cutter in the list, and the shortcuts start working without a relaunch. Until then Cutter registers no shortcuts, so it does not swallow key presses it cannot act on.

Cutter has no Dock icon. Open its settings from the menu bar icon, or by opening the app again while it runs.

## Signing

macOS ties the Accessibility permission to the app's code signature. So that the permission survives rebuilds, `build-app.sh` signs every build with the same self-signed certificate. It creates the certificate on the first build, in a keychain of its own under `~/Library/Application Support/Cutter/signing`. Your login keychain and keychain search list are not touched. See `scripts/signing.env` for details.

- To remove the certificate, delete that folder. The next build creates a new one, and macOS will ask for Accessibility access again.
- To build without it: `CUTTER_SIGNING=adhoc ./scripts/build-app.sh`. Access must then be granted again after every build.
- If Cutter is switched on under Accessibility but still says it needs access, the entry belongs to an older signature. Remove it with `tccutil reset Accessibility com.ericzakariasson.Cutter` and grant access again.

## Troubleshooting

```sh
build/Cutter.app/Contents/MacOS/Cutter --diagnose
```

prints the screens Cutter sees, the configured shortcuts, and whether macOS accepts each one. Run from a terminal, its "Accessibility access" line reports the terminal's permission, not Cutter's.

```sh
open -n build/Cutter.app --stdout /tmp/cutter-self-test.log --args --self-test
cat /tmp/cutter-self-test.log
```

checks placement end to end once Cutter has Accessibility access. On each screen it opens a small window of its own, applies every placement to it and reports where the window ended up. It moves no other window. A screen showing a full-screen app is skipped.

## Adding a placement

Add a case to `WindowAction` in `Sources/CutterCore/WindowAction.swift` with a title and the fraction of the screen it covers, and give it an icon in `Sources/Cutter/SettingsView.swift`. The compiler points at both places. The settings window, the menu and shortcut storage pick the new action up on their own.

## Layout

- `Sources/CutterCore`: actions, frame math, the shortcut model and its storage. No AppKit; covered by unit tests.
- `Sources/Cutter`: the app. Global shortcuts (`HotKeyCenter`), window control through the Accessibility API (`WindowManager`), the permission flow, the menu and the settings window.
- `scripts`: building, signing and testing.

## Known limits

- A window in native full screen ignores placements; leave full screen first.
- Some windows refuse a size (minimum sizes, fixed-size dialogs, terminals that resize in whole characters). Cutter then keeps the window against the screen edges the placement touches.
- The build is for this Mac's architecture only.
