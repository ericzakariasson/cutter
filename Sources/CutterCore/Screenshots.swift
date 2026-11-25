import Foundation

/// A screenshot file and when it was taken.
public struct Screenshot: Equatable, Hashable, Sendable {
    public var url: URL
    public var date: Date

    public init(url: URL, date: Date) {
        self.url = url
        self.date = date
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

/// Decides which files in a folder are screenshots, and lists the newest.
public enum ScreenshotFinder {
    /// The extended attribute macOS puts on every screenshot it saves, whatever the file
    /// is called and whatever language the Mac is set to.
    public static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    /// The formats the screenshot tool can be set to. Screen recordings are movies and
    /// are left out.
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "pdf"]

    /// File-name prefixes of macOS screenshots in English, now and before macOS 11. They
    /// are a fallback for files that lost the attribute, for example on the way through a
    /// sync service.
    public static let standardNamePrefixes = ["Screenshot", "Screen Shot"]

    /// Whether a file with this name counts as a screenshot.
    ///
    /// - Parameters:
    ///   - isMarkedAsScreenCapture: whether the file carries `screenCaptureAttribute`.
    ///   - namePrefix: the custom prefix from the screenshot settings, if one is set.
    public static func isScreenshot(fileName: String, isMarkedAsScreenCapture: Bool, namePrefix: String?) -> Bool {
        // The screenshot tool writes to a hidden file first and renames it when done.
        guard !fileName.hasPrefix(".") else {
            return false
        }
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(fileExtension) else {
            return false
        }
        if isMarkedAsScreenCapture {
            return true
        }
        var prefixes = standardNamePrefixes
        if let namePrefix, !namePrefix.isEmpty {
            prefixes.append(namePrefix)
        }
        return prefixes.contains { fileName.hasPrefix($0) }
    }

    /// The newest screenshots in a folder, newest first. Looks at the folder's own files
    /// only, not into subfolders. Throws what the file system throws, notably a
    /// permission error when macOS does not let the app read the folder.
    public static func recent(
        in folder: URL,
        namePrefix: String?,
        limit: Int,
        fileManager: FileManager = .default
    ) throws -> [Screenshot] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])

        var screenshots: [Screenshot] = []
        for file in files {
            let name = file.lastPathComponent
            // The cheap test on the name first; the attribute is only read for images.
            guard isScreenshot(fileName: name, isMarkedAsScreenCapture: true, namePrefix: namePrefix),
                  let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  isScreenshot(fileName: name, isMarkedAsScreenCapture: isMarkedAsScreenCapture(file), namePrefix: namePrefix),
                  let date = values.creationDate ?? values.contentModificationDate
            else {
                continue
            }
            screenshots.append(Screenshot(url: file, date: date))
        }
        return newest(screenshots, limit: limit)
    }

    /// The newest `limit` screenshots, newest first. Screenshots taken in the same instant
    /// are ordered by name, so the order is the same every time.
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
