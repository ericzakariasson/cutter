import Foundation

/// Which shortcut triggers which action.
///
/// Only the user's own choices are stored. An action without a stored choice uses its
/// default, so a later version can add defaults without overwriting what the user set.
public struct ShortcutConfiguration: Codable, Equatable, Sendable {
    /// A stored choice. A missing `combo` means the user cleared the shortcut.
    private struct Choice: Codable, Equatable, Sendable {
        var combo: KeyCombo?
    }

    /// Keyed by `WindowAction.rawValue`. Unknown keys are kept, so settings written by a
    /// newer version survive a round trip through an older one.
    private var choices: [String: Choice]

    public static let defaultShortcuts: [WindowAction: KeyCombo] = [
        .maximize: KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.control, .option]),
        .leftHalf: KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.control, .option]),
        .rightHalf: KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.control, .option]),
        .topHalf: KeyCombo(keyCode: KeyCode.upArrow, modifiers: [.control, .option]),
        .bottomHalf: KeyCombo(keyCode: KeyCode.downArrow, modifiers: [.control, .option]),
    ]

    public init() {
        self.choices = [:]
    }

    public init(from decoder: Decoder) throws {
        self.choices = try decoder.singleValueContainer().decode([String: Choice].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(choices)
    }

    public func shortcut(for action: WindowAction) -> KeyCombo? {
        if let choice = choices[action.rawValue] {
            return choice.combo
        }
        guard let combo = Self.defaultShortcuts[action] else {
            return nil
        }
        // A shortcut the user gave to another action is not also this action's default.
        // This matters when a new version adds a default the user already uses elsewhere.
        let isTakenByUserChoice = choices.contains { $0.key != action.rawValue && $0.value.combo == combo }
        return isTakenByUserChoice ? nil : combo
    }

    public func action(for combo: KeyCombo) -> WindowAction? {
        WindowAction.allCases.first { shortcut(for: $0) == combo }
    }

    /// Every action that has a shortcut, in `WindowAction.allCases` order.
    public var assignments: [(action: WindowAction, combo: KeyCombo)] {
        WindowAction.allCases.compactMap { action in
            shortcut(for: action).map { (action, $0) }
        }
    }

    /// Sets or clears an action's shortcut. A shortcut can trigger only one action, so if
    /// another action already uses it, that action loses it and is returned.
    @discardableResult
    public mutating func setShortcut(_ combo: KeyCombo?, for action: WindowAction) -> WindowAction? {
        var displaced: WindowAction?
        if let combo, let current = self.action(for: combo), current != action {
            choices[current.rawValue] = Choice(combo: nil)
            displaced = current
        }
        choices[action.rawValue] = Choice(combo: combo)
        return displaced
    }

    public mutating func resetToDefaults() {
        choices = [:]
    }

    /// Whether every action has exactly its default shortcut.
    public var isDefault: Bool {
        WindowAction.allCases.allSatisfy { shortcut(for: $0) == Self.defaultShortcuts[$0] }
    }
}

/// Where the configuration is kept. `UserDefaults` in the app; memory in tests.
public protocol ShortcutStorage {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data, forKey key: String)
}

extension UserDefaults: ShortcutStorage {
    public func setData(_ data: Data, forKey key: String) {
        set(data, forKey: key)
    }
}

public final class InMemoryShortcutStorage: ShortcutStorage {
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? {
        values[key]
    }

    public func setData(_ data: Data, forKey key: String) {
        values[key] = data
    }
}

/// Loads and saves the configuration.
public struct ShortcutStore {
    private let storage: ShortcutStorage
    private let key: String

    public init(storage: ShortcutStorage = UserDefaults.standard, key: String = "shortcuts") {
        self.storage = storage
        self.key = key
    }

    /// The saved configuration, or the defaults when nothing readable is saved.
    public func load() -> ShortcutConfiguration {
        guard let data = storage.data(forKey: key),
              let configuration = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data)
        else {
            return ShortcutConfiguration()
        }
        return configuration
    }

    public func save(_ configuration: ShortcutConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        storage.setData(data, forKey: key)
    }
}
