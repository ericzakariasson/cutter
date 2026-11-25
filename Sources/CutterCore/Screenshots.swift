import Foundation

/// A screenshot or screen recording file and when it was taken.
public struct Screenshot: Equatable, Hashable, Sendable {
    public var url: URL
    public var date: Date

    public init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }

    /// Whether this is a screen recording, a movie, and not a still picture.
    public var isRecording: Bool {
        ScreenshotFinder.recordingExtensions.contains(url.pathExtension.lowercased())
    }
}

/// What macOS calls the files it saves, which is how they start their names.
public struct ScreenshotNames: Equatable, Sendable {
    public var screenshot: [String]
    public var recording: [String]

    public init(screenshot: [String], recording: [String]) {
        self.screenshot = screenshot
        self.recording = recording
    }

    /// The English names, now and before macOS 11.
    public static let english = ScreenshotNames(screenshot: ["Screenshot", "Screen Shot"], recording: ["Screen Recording"])

    /// The English names plus the ones this Mac's language uses, read from the macOS
    /// screenshot tool itself.
    public static func system() -> ScreenshotNames {
        var names = english
        guard let tool = Bundle(path: "/System/Library/CoreServices/screencaptureui.app") else {
            return names
        }
        for (key, keyPath) in [("Screenshot", \ScreenshotNames.screenshot), ("Screen Recording", \ScreenshotNames.recording)] {
            let localized = tool.localizedString(forKey: key, value: key, table: nil)
            if !localized.isEmpty, !names[keyPath: keyPath].contains(localized) {
                names[keyPath: keyPath].append(localized)
            }
        }
        return names
    }
}

/// Where macOS saves screenshots.
public enum ScreenshotLocation {
    /// The preferences domain of the macOS screenshot tool. `location` is the folder set
    /// under Screenshot > Options, `name` a custom file-name prefix.
    public static let preferencesDomain = "com.apple.screencapture"

    /// The folder for a `location` setting. macOS uses the Desktop when the setting is
    /// missing or names something that is not a folder, and so does this.
    public static func folder(setting: String?, home: URL, isDirectory: (URL) -> Bool) -> URL {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        guard let setting = setting?.trimmingCharacters(in: .whitespacesAndNewlines), !setting.isEmpty else {
            return desktop
        }
        let path: String
        if setting == "~" {
            path = home.path
        } else if setting.hasPrefix("~/") {
            path = home.appendingPathComponent(String(setting.dropFirst(2))).path
        } else if setting.hasPrefix("/") {
            path = setting
        } else {
            return desktop
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        return isDirectory(folder) ? folder : desktop
    }

    /// The folder and file-name prefix this Mac is set to. Reads the setting only; the
    /// folder itself is not touched.
    public static func current(
        defaults: UserDefaults? = UserDefaults(suiteName: preferencesDomain),
        fileManager: FileManager = .default
    ) -> (folder: URL, namePrefix: String?) {
        let folder = folder(
            setting: defaults?.string(forKey: "location"),
            home: fileManager.homeDirectoryForCurrentUser
        ) { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return (folder, defaults?.string(forKey: "name"))
    }
}

/// What a look into the screenshot folder found, as numbers and ages only: nothing here
/// names a file or says what a picture shows. It goes into the log, to tell "the
/// screenshot is not in the folder yet" from "it is there and Cutter leaves it out".
public struct FolderSurvey: Equatable, Sendable {
    /// Entries in the folder, of any kind.
    public var items: Int
    /// Screenshots and recordings that count, before the limit.
    public var counting = 0
    /// How many of those are listed.
    public var shown = 0
    public var newestShown: Date?
    /// The newest picture or movie that is left out, hidden ones included.
    public var newestLeftOut: Date?
    /// The newest entry of any kind.
    public var newestItem: Date?

    public init(items: Int) {
        self.items = items
    }

    public func summary(now: Date = Date()) -> String {
        func age(_ date: Date?) -> String {
            guard let date else {
                return "none"
            }
            let seconds = now.timeIntervalSince(date)
            switch seconds {
            case ..<0: return "dated \(Int((-seconds).rounded())) s ahead"
            case ..<120: return "\(Int(seconds.rounded())) s old"
            case ..<7200: return "\(Int((seconds / 60).rounded())) min old"
            case ..<172_800: return "\(Int((seconds / 3600).rounded())) h old"
            default: return "\(Int((seconds / 86400).rounded())) d old"
            }
        }
        return "\(shown) shown of \(counting) that count, \(items) items in the folder; newest shown: \(age(newestShown)); "
            + "newest picture or movie left out: \(age(newestLeftOut)); newest item of any kind: \(age(newestItem))"
    }
}

/// Decides which files in a folder are screenshots, and lists the newest.
public enum ScreenshotFinder {
    /// The extended attribute macOS puts on every screenshot it saves, whatever the file
    /// is called and whatever language the Mac is set to.
    public static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// The formats the screenshot tool can be set to.
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "pdf"]

    /// The formats macOS saves screen recordings in.
    public static let recordingExtensions: Set<String> = ["mov", "mp4"]

    public enum Kind: Equatable, Sendable {
        case screenshot
        case recording
    }

    /// What a file with this name is: a screenshot, a screen recording, or neither.
    ///
    /// The mark macOS puts on the file decides, whatever the file is called. The name is
    /// the fallback for files that lost the mark, for example on the way through a sync
    /// service.
    ///
    /// - Parameters:
    ///   - isMarkedAsScreenCapture: whether the file carries `screenCaptureAttribute`.
    ///   - namePrefix: the custom prefix from the screenshot settings, if one is set.
    ///   - names: what macOS calls its screenshots and recordings.
    public static func kind(
        fileName: String,
        isMarkedAsScreenCapture: Bool,
        namePrefix: String?,
        names: ScreenshotNames = .english
    ) -> Kind? {
        // The screenshot tool writes to a hidden file first and renames it when done.
        guard !fileName.hasPrefix(".") else {
            return nil
        }
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let kind: Kind
        var prefixes: [String]
        if imageExtensions.contains(fileExtension) {
            kind = .screenshot
            prefixes = names.screenshot
        } else if recordingExtensions.contains(fileExtension) {
            kind = .recording
            prefixes = names.recording
        } else {
            return nil
        }
        if isMarkedAsScreenCapture {
            return kind
        }
        if let namePrefix, !namePrefix.isEmpty {
            prefixes.append(namePrefix)
        }
        return prefixes.contains { fileName.hasPrefix($0) } ? kind : nil
    }

    /// Whether a file with this name counts as a still screenshot.
    public static func isScreenshot(fileName: String, isMarkedAsScreenCapture: Bool, namePrefix: String?) -> Bool {
        kind(fileName: fileName, isMarkedAsScreenCapture: isMarkedAsScreenCapture, namePrefix: namePrefix) == .screenshot
    }

    /// The newest screenshots and screen recordings in a folder, newest first. Looks at
    /// the folder's own files only, not into subfolders. Throws what the file system
    /// throws, notably a permission error when macOS does not let the app read the folder.
    public static func recent(
        in folder: URL,
        namePrefix: String?,
        limit: Int,
        names: ScreenshotNames = .english,
        fileManager: FileManager = .default
    ) throws -> [Screenshot] {
        try look(in: folder, namePrefix: namePrefix, limit: limit, names: names, fileManager: fileManager).screenshots
    }

    /// The listing together with what the folder held, in numbers.
    public static func look(
        in folder: URL,
        namePrefix: String?,
        limit: Int,
        names: ScreenshotNames = .english,
        fileManager: FileManager = .default
    ) throws -> (screenshots: [Screenshot], survey: FolderSurvey) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])

        var survey = FolderSurvey(items: files.count)
        var screenshots: [Screenshot] = []
        for file in files {
            let name = file.lastPathComponent
            let values = try? file.resourceValues(forKeys: Set(keys))
            let date = values?.creationDate ?? values?.contentModificationDate
            survey.newestItem = later(survey.newestItem, date)

            // A hidden picture or movie is one the screenshot tool is still writing.
            let visibleName = name.hasPrefix(".") ? String(name.dropFirst()) : name
            let isPictureOrMovie = kind(fileName: visibleName, isMarkedAsScreenCapture: true, namePrefix: namePrefix, names: names) != nil
            // The cheap test on the name first; the mark is only read for pictures and movies.
            guard isPictureOrMovie, !name.hasPrefix("."),
                  values?.isRegularFile == true,
                  kind(fileName: name, isMarkedAsScreenCapture: isMarkedAsScreenCapture(file), namePrefix: namePrefix, names: names) != nil,
                  let date
            else {
                if isPictureOrMovie, values?.isRegularFile == true {
                    survey.newestLeftOut = later(survey.newestLeftOut, date)
                }
                continue
            }
            screenshots.append(Screenshot(url: file, date: date))
        }
        let shown = newest(screenshots, limit: limit)
        survey.counting = screenshots.count
        survey.shown = shown.count
        survey.newestShown = shown.first?.date
        return (shown, survey)
    }

    private static func later(_ first: Date?, _ second: Date?) -> Date? {
        guard let first else {
            return second
        }
        guard let second else {
            return first
        }
        return max(first, second)
    }

    public static func newest(_ screenshots: [Screenshot], limit: Int) -> [Screenshot] {
        let sorted = screenshots.sorted { first, second in
            if first.date != second.date {
                return first.date > second.date
            }
            return first.url.lastPathComponent > second.url.lastPathComponent
        }
        return Array(sorted.prefix(max(limit, 0)))
    }

    /// Whether the file carries the screenshot attribute with a true value.
    public static func isMarkedAsScreenCapture(_ file: URL) -> Bool {
        file.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return false
            }
            let size = getxattr(path, screenCaptureAttribute, nil, 0, 0, 0)
            guard size > 0 else {
                return false
            }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, screenCaptureAttribute, buffer.baseAddress, size, 0, 0)
            }
            guard read == size, let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
                return false
            }
            // macOS stores a boolean; a number is accepted as well.
            return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
        }
    }

    /// Marks a file the way macOS marks a screenshot. For tests and the demo snapshot.
    public static func markAsScreenCapture(_ file: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = file.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return data.withUnsafeBytes { buffer in
                setxattr(path, screenCaptureAttribute, buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        if result != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// Moving the selection through a grid of items laid out row by row.
public enum GridSelection {
    public enum Move: Sendable {
        case left, right, up, down, first, last
    }

    /// The index selected after a move. With nothing selected, any move selects the
    /// first item. At an edge the selection stays where it is; moving down from the row
    /// above a shorter last row goes to the last item.
    public static func index(after move: Move, from index: Int?, count: Int, columns: Int) -> Int? {
        guard count > 0, columns > 0 else {
            return nil
        }
        guard let index, (0..<count).contains(index) else {
            return move == .last ? count - 1 : 0
        }
        switch move {
        case .left:
            return max(index - 1, 0)
        case .right:
            return min(index + 1, count - 1)
        case .up:
            return index >= columns ? index - columns : index
        case .down:
            if index + columns < count {
                return index + columns
            }
            let lastRow = (count - 1) / columns
            return index / columns < lastRow ? count - 1 : index
        case .first:
            return 0
        case .last:
            return count - 1
        }
    }
}
