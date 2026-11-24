import Foundation
import ServiceManagement

/// Launch at login through `SMAppService`, which registers the app bundle itself. It needs
/// no helper app and shows up under System Settings > General > Login Items.
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .requiresApproval {
            message = "Allow Cutter under System Settings > General > Login Items."
        }
    }

    func setEnabled(_ enabled: Bool) {
        message = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "Could not change the login item: \(error.localizedDescription)"
        }
        refresh()
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "off"
        case .enabled: return "on"
        case .requiresApproval: return "waiting for approval in System Settings"
        case .notFound: return "not available (app not found)"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }
}
