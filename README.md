# Cutter

A macOS menu bar app that moves and resizes the focused window with global keyboard shortcuts, and shows your most recent screenshots on another.

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
| Show Recent Screenshots | ⌃⌥S |

Every shortcut can be changed or removed in the settings window. With several displays, a placement applies to the display the window is on.

macOS draws the shortcut glyphs in Cutter's menu, and on macOS 26 it draws arrow keys as filled triangles, so the menu shows ⌃⌥◀ where Settings shows ⌃⌥←.

## Moving between displays

Move to Previous Display and Move to Next Display send the focused window to another display. Pressing one repeatedly cycles through all displays and wraps around at the ends; with one display they do nothing.

- **Order.** The displays are ordered as they are arranged in System Settings > Displays: rows from top to bottom, and left to right within a row. With one display above another, ⌃⌥↑ goes to the upper one and ⌃⌥↓ to the lower one. With displays side by side, ⌃⌥↑ goes left and ⌃⌥↓ goes right. With two displays, either shortcut swaps.
- **Size and position.** The window keeps its place within the visible area: a maximized window stays maximized, a left half stays a left half, and any other window covers the same fraction of the new display at the same relative position, so it grows or shrinks with the display. It always ends up fully inside the visible area.

## Recent screenshots

⌃⌥S, or Show Recent Screenshots in the menu, opens a panel with your newest screenshots and screen recordings as thumbnails, newest first. The same shortcut closes it again, as do Escape and a click anywhere else.

| In the panel | Keyboard | Mouse |
| --- | --- | --- |
| Choose a screenshot | Arrow keys, Home, End | Click |
| Draw on it or crop it | ⌘E | Double-click, the Markup button, or right-click > Markup |
| Open it in its app | ↩ | The Open button, or right-click > Open |
| Copy it to the clipboard | ⌘C | The Copy button, or right-click > Copy |
| Show it in Finder | ⌘↩ or ⌘R | The Show in Finder button, or right-click |
| Use it in another app | | Drag the thumbnail there |

The panel has the keyboard while it is open and gives it back when it closes. It closes after opening, copying or showing a screenshot in Finder, after a thumbnail has been dragged out, and whenever your attention goes elsewhere: a click outside it, another app coming forward, or anything else taking the keyboard. It makes way for Markup and comes back when the editing is over. A copied screenshot pastes as a picture where pictures go and as a file in Finder; a copied recording pastes as a file.

**Markup.** Double-clicking a screenshot opens it in macOS's own Markup editor, the one behind the screenshot thumbnail, Quick Look and Mail: pen, shapes, arrows, text and crop. Cutter shows the screenshot in a window and Markup opens on it. Done saves the edited picture over the screenshot file, as macOS does when you mark up a screenshot from its thumbnail: same name, same format, same place in the list. There is no copy of the original, so keep one yourself if you may want it back. Cancel leaves the file as it was. Either way the panel comes back afterwards with that screenshot selected, so an edit ends where it began. The window also has an Open in Preview button, where the same tools are in the Markup toolbar. A screen recording cannot be drawn on; double-clicking it opens it in its app, where it can be trimmed.

- **How it looks.** On macOS 26 the panel is a sheet of the system's Liquid Glass; on macOS 13 to 15 it uses the standard blurred material. The selected screenshot is marked the way Finder marks a selected icon, in your accent colour.
- **Where it looks.** In the folder macOS saves screenshots to: the one chosen under Options in the Screenshot toolbar (⇧⌘5), or the Desktop when none was chosen.
- **What counts as a screenshot.** A picture that macOS marked as a screenshot when it saved it, whatever the file is called now, or one whose name starts with "Screenshot" (in English or in your Mac's language) or with your own screenshot name prefix.
- **What counts as a recording.** A `.mov` or `.mp4` that macOS marked as a screen capture, or one whose name starts with "Screen Recording". Recordings have a play badge. Other movies in the folder are not shown, and neither are screenshots or recordings moved out of it.
- **How many.** The newest 30.
- **When it reads the folder.** Each time the panel opens, and again while it is open whenever something lands in the folder. Never while the panel is closed.
- **A screenshot you have just taken.** With the corner preview on, macOS saves a screenshot only when the preview has gone, about five seconds after you took it. Until then there is no file for Cutter to show. If the panel is open at that moment, the screenshot appears at the top by itself. To have screenshots saved at once, switch off Show Floating Thumbnail under Options in the Screenshot toolbar (⇧⌘5).
- **Permission.** If the folder is the Desktop, Documents or Downloads, macOS asks once, the first time the panel opens, whether Cutter may access files there. The panel closes while the question is up; open it again after answering. Cutter reads the screenshots to show them, and changes a file only when you press Done in Markup. Without the permission the panel says so; it can be given later under System Settings > Privacy & Security > Files and Folders. This feature does not need Accessibility access.

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

## First run

Cutter needs Accessibility access to move other apps' windows. On first launch it opens its settings window and explains this. Click **Open Accessibility Settings…**, turn on Cutter in the list, and the shortcuts start working without a relaunch. Until then Cutter registers none of its window shortcuts, so it does not swallow key presses it cannot act on. Showing the recent screenshots works without it.

Cutter has no Dock icon. Open its settings from the menu bar icon, or by opening the app again while it runs.

## Signing

macOS ties the Accessibility permission to the app's code signature. So that the permission survives rebuilds, `build-app.sh` signs every build with the same self-signed certificate. It creates the certificate on the first build, in a keychain of its own under `~/Library/Application Support/Cutter/signing`. Your login keychain and keychain search list are not touched.

**This weakens the Accessibility permission, and you should know how.** The signing keychain's password is written in `scripts/signing.env` and the keychain never locks. Any process running as you can therefore sign a program of its choice as Cutter. macOS then treats that program as Cutter, so it has Cutter's Accessibility access without asking you: it can read and control every app's windows and send them input. Without the certificate, such a process would have to get you to grant it access itself. The certificate gives nothing to an attacker who cannot already run code as you.

- To avoid the trade-off, build with `CUTTER_SIGNING=adhoc ./scripts/build-app.sh` and delete the signing folder. Access must then be granted again after every build.
- To remove the certificate, delete that folder. The next build creates a new one, and macOS will ask for Accessibility access again.
- If Cutter is switched on under Accessibility but still says it needs access, the entry belongs to an older signature. Remove it with `tccutil reset Accessibility com.ericzakariasson.Cutter` and grant access again.

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

- `Sources/CutterCore`: actions, frame math, the shortcut model and its storage, and the rules for finding screenshots. No AppKit; covered by unit tests.
- `Sources/Cutter`: the app. Global shortcuts (`HotKeyCenter`), window control through the Accessibility API (`WindowManager`), the permission flow, the menu, the settings window and the screenshots panel (`ScreenshotPanelController`).
- `Sources/CutterDemo`: draws the animation above, `docs/demo.gif`, off-screen. Run `./scripts/make-demo.sh` to regenerate it after changing the placements or the default shortcuts; add `--mp4 <file>` for an H.264 movie as well.
- `scripts`: building, signing and testing. `make-icon.swift` draws `Support/AppIcon.icns`.

## Known limits

- A window in native full screen ignores placements and display moves; leave full screen first.
- A display that is showing a full-screen app has no desktop for another window to land on, so a window sent there may not appear.
- An app that has stopped responding cannot be moved. Cutter waits about a second for it and then beeps.
- Some windows refuse a size (minimum sizes, fixed-size dialogs, terminals that resize in whole characters). Cutter then keeps the window against the screen edges the placement touches.
- The build is for this Mac's architecture only.
