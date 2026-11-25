import AppKit
import Testing

@testable import Cutter

/// The order in which the emoji picker is asked for. Nothing here opens a picker, reads
/// another app's menus or sends a key: every step is the test's own.
@MainActor
@Suite struct EmojiPickerTests {
    private final class World {
        var front: (pid: pid_t, bundleID: String?)? = (pid: 4242, bundleID: "com.example.Notes")
        var isTrusted = true
        var menu = EmojiPicker.MenuAnswer.pressed
        var inputSourceWorks = true
        var keystrokeWorks = true
        var time = Date(timeIntervalSinceReferenceDate: 1_000)

        var shownInCutter = 0
        var menusAsked: [pid_t] = []
        var inputSourceSelections = 0
        var keystrokes = 0
        var log: [String] = []
        var results: [EmojiPicker.Route?] = []
        var later: [() -> Void] = []

        lazy var picker: EmojiPicker = {
            var environment = EmojiPicker.Environment()
            environment.frontApp = { [unowned self] in front }
            environment.ownPID = 1
            environment.isTrusted = { [unowned self] in isTrusted }
            environment.showInCutter = { [unowned self] in shownInCutter += 1 }
            environment.pressMenuItem = { [unowned self] pid in
                menusAsked.append(pid)
                return menu
            }
            environment.selectInputSource = { [unowned self] in
                inputSourceSelections += 1
                return inputSourceWorks
            }
            environment.postKeystroke = { [unowned self] in
                keystrokes += 1
                return keystrokeWorks
            }
            environment.whatIsUp = { "nothing looked at" }
            environment.log = { [unowned self] in log.append($0) }
            environment.inBackground = { $0() }
            environment.onMain = { $0() }
            environment.later = { [unowned self] _, work in later.append(work) }
            environment.now = { [unowned self] in time }
            let picker = EmojiPicker(environment: environment)
            picker.onResult = { [unowned self] in results.append($0) }
            return picker
        }()
    }

    /// The app in front opens its own picker: nothing else is tried on top of it.
    @Test func theAppsOwnMenuItemIsPressedFirst() {
        let world = World()
        world.picker.show()

        #expect(world.menusAsked == [4242])
        #expect(world.results == [.menuItem])
        #expect(world.inputSourceSelections == 0)
        #expect(world.keystrokes == 0)
        #expect(world.shownInCutter == 0)
        #expect(world.log == ["pressed the Emoji & Symbols menu item of com.example.Notes"])
    }

    /// Pressing twice would close the picker again, so a press the app was slow to
    /// confirm is taken as a press.
    @Test func aPressTheAppWasSlowToConfirmIsNotFollowedByAnotherWay() {
        let world = World()
        world.menu = .pressedWithoutAnswer
        world.picker.show()

        #expect(world.results == [.menuItem])
        #expect(world.inputSourceSelections == 0)
        #expect(world.keystrokes == 0)
    }

    @Test(arguments: [EmojiPicker.MenuAnswer.notFound, .disabled, .failed(-25204)])
    func anAppWithoutAUsableMenuItemGetsTheInputSource(answer: EmojiPicker.MenuAnswer) {
        let world = World()
        world.menu = answer
        world.picker.show()

        #expect(world.menusAsked == [4242])
        #expect(world.inputSourceSelections == 1)
        #expect(world.keystrokes == 0)
        #expect(world.results == [.inputSource])
        #expect(world.log.count == 2)
        #expect(world.log.last == "selected the Character Viewer input source")
    }

    /// Reading another app's menus takes Accessibility access. Without it the input
    /// source still opens the picker, which is why the shortcut needs no access.
    @Test func withoutAccessibilityAccessTheMenusAreLeftAloneAndTheInputSourceIsUsed() {
        let world = World()
        world.isTrusted = false
        world.picker.show()

        #expect(world.menusAsked.isEmpty)
        #expect(world.inputSourceSelections == 1)
        #expect(world.results == [.inputSource])
        #expect(world.log.first == "no Accessibility access, so the menu item of com.example.Notes was not tried")
    }

    /// Control-Command-Space is only the last resort: macOS may have given the picker
    /// other keys.
    @Test func theKeystrokeIsSentOnlyWhenTheInputSourceCannotBeSelected() {
        let world = World()
        world.menu = .notFound
        world.inputSourceWorks = false
        world.picker.show()

        #expect(world.inputSourceSelections == 1)
        #expect(world.keystrokes == 1)
        #expect(world.results == [.keystroke])
    }

    /// Sending keys takes Accessibility access as well.
    @Test func withNoWayLeftNothingIsOpenedAndTheLogSaysSo() {
        let world = World()
        world.isTrusted = false
        world.inputSourceWorks = false
        world.picker.show()

        #expect(world.keystrokes == 0)
        #expect(world.results == [nil])
        #expect(world.log.last == "the input source could not be selected and no keystroke could be sent; nothing opened")
        #expect(world.later.isEmpty)
    }

    @Test func aFailedKeystrokeIsReportedAsNothingOpened() {
        let world = World()
        world.menu = .notFound
        world.inputSourceWorks = false
        world.keystrokeWorks = false
        world.picker.show()
        #expect(world.results == [nil])
    }

    /// With Cutter itself in front, its settings window for one, Cutter opens its own.
    @Test func inCutterItselfThePickerIsCuttersOwn() {
        let world = World()
        world.front = (pid: 1, bundleID: "com.ericzakariasson.Cutter")
        world.picker.show()

        #expect(world.shownInCutter == 1)
        #expect(world.menusAsked.isEmpty)
        #expect(world.inputSourceSelections == 0)
        #expect(world.results == [.cutterItself])
    }

    @Test func withNoAppInFrontTheInputSourceIsUsed() {
        let world = World()
        world.front = nil
        world.picker.show()

        #expect(world.menusAsked.isEmpty)
        #expect(world.results == [.inputSource])
    }

    /// The picker opens and closes on the same request, so a second one right behind
    /// the first, from a key held down, must not undo it.
    @Test func aSecondRequestRightBehindTheFirstIsIgnored() {
        let world = World()
        world.picker.show()
        world.time += 0.1
        world.picker.show()
        #expect(world.menusAsked.count == 1)

        world.time += EmojiPicker.repeatInterval
        world.picker.show()
        #expect(world.menusAsked.count == 2)
        #expect(world.results == [.menuItem, .menuItem])
    }

    /// The log names the app by its identifier and the way taken. An app without an
    /// identifier is not named at all.
    @Test func theLogNamesTheWayAndTheAppAndNothingElse() {
        let world = World()
        world.front = (pid: 77, bundleID: nil)
        world.menu = .notFound
        world.picker.show()
        #expect(world.log == [
            "an app without an identifier has no Emoji & Symbols menu item",
            "selected the Character Viewer input source",
        ])

        // The look afterwards is one more line, and asks for nothing.
        #expect(world.later.count == 1)
        world.later.removeFirst()()
        #expect(world.log.last == "0.6 s later: nothing looked at")
        #expect(world.inputSourceSelections == 1)
        #expect(world.keystrokes == 0)
    }

    @Test func theMarksItLooksForAreTheSystemsOwn() {
        #expect(EmojiPicker.menuItemIdentifier == "orderFrontCharacterPalette:")
        #expect(EmojiPicker.inputSourceID == "com.apple.CharacterPaletteIM")
    }
}
