import Foundation
import Testing

@testable import CutterCore

/// A temporary folder standing in for the Desktop. Every file in it is made up here; the
/// tests never look at a real screenshot folder.
private final class SampleFolder {
    let url: URL
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("CutterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Adds a file created `minute` minutes after the start.
    @discardableResult
    func add(_ name: String, minute: Int, marked: Bool = false) throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data("sample".utf8).write(to: file)
        if marked {
            try ScreenshotFinder.markAsScreenCapture(file)
        }
        let date = start.addingTimeInterval(TimeInterval(minute * 60))
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: file.path)
        return file
    }

    func names(limit: Int = 30, namePrefix: String? = nil) throws -> [String] {
        try ScreenshotFinder.recent(in: url, namePrefix: namePrefix, limit: limit).map(\.url.lastPathComponent)
    }
}

@Suite struct ScreenshotLocationTests {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func folder(_ setting: String?, existing: Set<String> = []) -> String {
        ScreenshotLocation.folder(setting: setting, home: home) { existing.contains($0.path) }.path
    }

    @Test func withoutASettingScreenshotsGoToTheDesktop() {
        #expect(folder(nil) == "/Users/someone/Desktop")
        #expect(folder("") == "/Users/someone/Desktop")
        #expect(folder("  ") == "/Users/someone/Desktop")
    }

    @Test func aFolderThatExistsIsUsed() {
        #expect(folder("/Users/someone/Pictures/Screenshots", existing: ["/Users/someone/Pictures/Screenshots"]) == "/Users/someone/Pictures/Screenshots")
        #expect(folder("/Users/someone/Documents/", existing: ["/Users/someone/Documents"]) == "/Users/someone/Documents")
    }

    @Test func aTildeStandsForTheHomeFolder() {
        #expect(folder("~/Shots", existing: ["/Users/someone/Shots"]) == "/Users/someone/Shots")
        #expect(folder("~", existing: ["/Users/someone"]) == "/Users/someone")
    }

    /// macOS falls back to the Desktop when the folder is gone, and so does Cutter.
    @Test func aMissingFolderFallsBackToTheDesktop() {
        #expect(folder("/Volumes/Gone/Shots") == "/Users/someone/Desktop")
        #expect(folder("~/Shots") == "/Users/someone/Desktop")
    }

    @Test func somethingThatIsNotAPathFallsBackToTheDesktop() {
        #expect(folder("Shots", existing: ["/Users/someone/Shots"]) == "/Users/someone/Desktop")
    }
}

@Suite struct ScreenshotRuleTests {
    private func counts(_ name: String, marked: Bool = false, prefix: String? = nil) -> Bool {
        ScreenshotFinder.isScreenshot(fileName: name, isMarkedAsScreenCapture: marked, namePrefix: prefix)
    }

    @Test func aMarkedImageIsAScreenshotWhateverItIsCalled() {
        #expect(counts("Skärmavbild 2026-11-25 kl. 09.12.33.png", marked: true))
        #expect(counts("Bildschirmfoto 2026-11-25 um 09.12.33.png", marked: true))
        #expect(counts("renamed.jpg", marked: true))
    }

    @Test func anUnmarkedImageCountsByItsEnglishName() {
        #expect(counts("Screenshot 2026-11-25 at 09.12.33.png"))
        #expect(counts("Screen Shot 2020-03-01 at 10.00.00.png"))
        #expect(!counts("Holiday.png"))
        #expect(!counts("My Screenshot.png"))
    }

    @Test func aCustomNamePrefixCounts() {
        #expect(counts("Capture 2026-11-25 at 09.12.33.png", prefix: "Capture"))
        #expect(!counts("Capture 2026-11-25 at 09.12.33.png"))
        #expect(!counts("Holiday.png", prefix: ""))
    }

    @Test func everyFormatTheScreenshotToolWritesCounts() {
        for fileExtension in ["png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "pdf", "PNG"] {
            #expect(counts("Screenshot 1.\(fileExtension)"))
        }
    }

    @Test func recordingsAreNotStillScreenshotsAndOtherFilesDoNotCount() {
        #expect(!counts("Screen Recording 2026-11-25 at 09.12.33.mov", marked: true))
        #expect(!counts("Screenshot notes.txt", marked: true))
        #expect(!counts("Screenshot", marked: true))
    }

    /// The screenshot tool writes to a hidden file first and renames it when done.
    @Test func aHiddenFileDoesNotCount() {
        #expect(!counts(".Screenshot 2026-11-25 at 09.12.33.png", marked: true))
    }
}

@Suite struct ScreenRecordingTests {
    private func kind(_ name: String, marked: Bool = false, prefix: String? = nil, names: ScreenshotNames = .english) -> ScreenshotFinder.Kind? {
        ScreenshotFinder.kind(fileName: name, isMarkedAsScreenCapture: marked, namePrefix: prefix, names: names)
    }

    @Test func aMarkedMovieIsARecordingWhateverItIsCalled() {
        #expect(kind("Skärminspelning 1.mov", marked: true) == .recording)
        #expect(kind("renamed.mp4", marked: true) == .recording)
    }

    @Test func anUnmarkedMovieCountsByItsName() {
        #expect(kind("Screen Recording 2026-11-25 at 09.12.33.mov") == .recording)
        #expect(kind("Holiday.mov") == nil)
        // A movie is not a screenshot just because it is named like one.
        #expect(kind("Screenshot 1.mov") == nil)
        #expect(kind("Screen Recording 1.png") == nil)
    }

    @Test func namesInTheMacsOwnLanguageCount() {
        let swedish = ScreenshotNames(screenshot: ["Screenshot", "Skärmavbild"], recording: ["Screen Recording", "Skärminspelning"])
        #expect(kind("Skärminspelning 2026-11-25 kl. 09.12.33.mov", names: swedish) == .recording)
        #expect(kind("Skärmavbild 2026-11-25 kl. 09.12.33.png", names: swedish) == .screenshot)
        #expect(kind("Skärminspelning 1.mov") == nil)
    }

    @Test func theSystemsNamesIncludeTheEnglishOnes() {
        let names = ScreenshotNames.system()
        #expect(names.screenshot.contains("Screenshot"))
        #expect(names.recording.contains("Screen Recording"))
    }

    @Test func recordingsAreListedAmongTheScreenshotsByTime() throws {
        let folder = try SampleFolder()
        try folder.add("Screenshot A.png", minute: 1)
        try folder.add("Screen Recording B.mov", minute: 2)
        try folder.add("Screenshot C.png", minute: 3)
        try folder.add("clip.mp4", minute: 4, marked: true)
        try folder.add("Holiday.mov", minute: 5)

        let found = try ScreenshotFinder.recent(in: folder.url, namePrefix: nil, limit: 10)
        #expect(found.map(\.url.lastPathComponent) == ["clip.mp4", "Screenshot C.png", "Screen Recording B.mov", "Screenshot A.png"])
        #expect(found.map(\.isRecording) == [true, false, true, false])
    }

    @Test func aHiddenRecordingBeingWrittenDoesNotCount() {
        #expect(kind(".Screen Recording 1.mov", marked: true) == nil)
    }
}

@Suite struct ScreenshotFinderTests {
    @Test func listsScreenshotsNewestFirst() throws {
        let folder = try SampleFolder()
        try folder.add("Screenshot A.png", minute: 1)
        try folder.add("Screenshot C.png", minute: 3)
        try folder.add("Screenshot B.png", minute: 2)
        #expect(try folder.names() == ["Screenshot C.png", "Screenshot B.png", "Screenshot A.png"])
    }

    @Test func findsMarkedFilesWhateverTheirNames() throws {
        let folder = try SampleFolder()
        try folder.add("Skärmavbild 1.png", minute: 1, marked: true)
        try folder.add("renamed.jpg", minute: 2, marked: true)
        try folder.add("Holiday.png", minute: 3)
        #expect(try folder.names() == ["renamed.jpg", "Skärmavbild 1.png"])
    }

    @Test func leavesOutEverythingThatIsNotAScreenshot() throws {
        let folder = try SampleFolder()
        try folder.add("Screenshot 1.png", minute: 1, marked: true)
        try folder.add("Holiday video.mov", minute: 2)
        try folder.add("Notes.txt", minute: 3)
        try folder.add("Holiday.png", minute: 4)
        try folder.add(".Screenshot 2.png", minute: 5, marked: true)
        // A folder with a screenshot's name, and a screenshot inside a subfolder.
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("Screenshot folder.png"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("Old"), withIntermediateDirectories: true)
        try Data().write(to: folder.url.appendingPathComponent("Old/Screenshot 0.png"))
        #expect(try folder.names() == ["Screenshot 1.png"])
    }

    @Test func keepsOnlyTheNewestUpToTheLimit() throws {
        let folder = try SampleFolder()
        for index in 1...8 {
            try folder.add("Screenshot \(index).png", minute: index)
        }
        #expect(try folder.names(limit: 3) == ["Screenshot 8.png", "Screenshot 7.png", "Screenshot 6.png"])
        #expect(try folder.names(limit: 0).isEmpty)
    }

    @Test func reportsWhenEachWasTaken() throws {
        let folder = try SampleFolder()
        let file = try folder.add("Screenshot 1.png", minute: 7)
        let found = try ScreenshotFinder.recent(in: folder.url, namePrefix: nil, limit: 5)
        #expect(found.count == 1)
        #expect(found.first?.url.lastPathComponent == file.lastPathComponent)
        #expect(found.first?.date == Date(timeIntervalSinceReferenceDate: 800_000_000 + 7 * 60))
    }

    @Test func anEmptyFolderHasNoScreenshots() throws {
        #expect(try SampleFolder().names().isEmpty)
    }

    @Test func aFolderThatCannotBeReadThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("CutterTests-missing-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try ScreenshotFinder.recent(in: missing, namePrefix: nil, limit: 5)
        }
    }

    @Test func theMarkIsReadBackOnlyFromMarkedFiles() throws {
        let folder = try SampleFolder()
        let marked = try folder.add("a.png", minute: 1, marked: true)
        let plain = try folder.add("b.png", minute: 2)
        #expect(ScreenshotFinder.isMarkedAsScreenCapture(marked))
        #expect(!ScreenshotFinder.isMarkedAsScreenCapture(plain))
        #expect(!ScreenshotFinder.isMarkedAsScreenCapture(folder.url.appendingPathComponent("missing.png")))
    }

    @Test func screenshotsFromTheSameInstantKeepAStableOrder() {
        let date = Date(timeIntervalSinceReferenceDate: 1)
        let screenshots = ["b", "c", "a"].map { Screenshot(url: URL(fileURLWithPath: "/tmp/\($0).png"), date: date) }
        #expect(ScreenshotFinder.newest(screenshots, limit: 10).map(\.url.lastPathComponent) == ["c.png", "b.png", "a.png"])
        #expect(ScreenshotFinder.newest(screenshots.reversed(), limit: 10).map(\.url.lastPathComponent) == ["c.png", "b.png", "a.png"])
    }
}

@Suite struct GridSelectionTests {
    /// Twelve items in rows of five: 0-4, 5-9, 10-11.
    private func move(_ move: GridSelection.Move, from index: Int?, count: Int = 12) -> Int? {
        GridSelection.index(after: move, from: index, count: count, columns: 5)
    }

    @Test func leftAndRightStepThroughTheItemsAndStopAtTheEnds() {
        #expect(move(.right, from: 0) == 1)
        #expect(move(.right, from: 4) == 5)
        #expect(move(.right, from: 11) == 11)
        #expect(move(.left, from: 5) == 4)
        #expect(move(.left, from: 0) == 0)
    }

    @Test func upAndDownMoveByARow() {
        #expect(move(.down, from: 1) == 6)
        #expect(move(.up, from: 6) == 1)
        #expect(move(.up, from: 3) == 3)
        #expect(move(.down, from: 10) == 10)
    }

    /// Below item 8 there is nothing; the last row is shorter. Down goes to the last item.
    @Test func downOntoAShorterLastRowGoesToTheLastItem() {
        #expect(move(.down, from: 8) == 11)
        #expect(move(.down, from: 5) == 10)
    }

    @Test func firstAndLast() {
        #expect(move(.first, from: 7) == 0)
        #expect(move(.last, from: 7) == 11)
    }

    @Test func withNothingSelectedAMoveSelectsTheFirstItem() {
        #expect(move(.right, from: nil) == 0)
        #expect(move(.down, from: nil) == 0)
        #expect(move(.last, from: nil) == 11)
        #expect(move(.left, from: 99) == 0)
    }

    @Test func anEmptyGridHasNoSelection() {
        #expect(move(.right, from: nil, count: 0) == nil)
        #expect(move(.down, from: 0, count: 0) == nil)
    }

    @Test func aSingleRowIgnoresUpAndDown() {
        #expect(move(.down, from: 1, count: 3) == 1)
        #expect(move(.up, from: 1, count: 3) == 1)
    }
}
