import CutterCore
import SwiftUI

extension WindowAction {
    /// SF Symbol shown next to the action in the settings window and the menu.
    var symbolName: String {
        switch self {
        case .maximize: return "rectangle.inset.filled"
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        case .topHalf: return "rectangle.tophalf.inset.filled"
        case .bottomHalf: return "rectangle.bottomhalf.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .previousDisplay: return "arrow.up.backward.square"
        case .nextDisplay: return "arrow.down.forward.square"
        case .toggleFullScreen: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var recorder: ShortcutRecorder
    @ObservedObject var loginItem: LoginItem

    /// The content scrolls instead of growing past this, so the window fits small screens.
    let maxHeight: CGFloat

    @State private var contentHeight: CGFloat = 600

    static let width: CGFloat = 480

    var body: some View {
        ScrollView(.vertical) {
            form
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(width: Self.width, height: min(contentHeight, maxHeight))
    }

    private var form: some View {
        Form {
            if !permission.isTrusted {
                Section {
                    AccessibilityRequestView(permission: permission)
                }
            }

            Section {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action, model: model, recorder: recorder)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Group {
                    if let warning = recorder.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text(model.notice ?? "Click a shortcut to change it, then press the new keys. ⌫ removes it, ⎋ cancels.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Launch Cutter at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if let message = loginItem.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if permission.isTrusted {
                    LabeledContent("Accessibility access") {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("General")
            }

            Section {
                HStack {
                    Button("Restore Default Shortcuts") {
                        recorder.cancel()
                        model.resetToDefaults()
                    }
                    .disabled(model.configuration.isDefault)
                    Spacer()
                    Text("Cutter \(AppInfo.version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AccessibilityRequestView: View {
    @ObservedObject var permission: AccessibilityPermission

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Cutter needs Accessibility access")
                    .font(.headline)
                Text("macOS lets an app move and resize other apps' windows only when you allow it under Privacy & Security > Accessibility. Cutter uses the access for that and nothing else. Until then its shortcuts are off.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Turn on Cutter in the list that opens. The shortcuts start working right away, without a relaunch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings…") {
                    permission.requestAccess()
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRow: View {
    let action: WindowAction
    @ObservedObject var model: AppModel
    @ObservedObject var recorder: ShortcutRecorder

    private var combo: KeyCombo? {
        model.configuration.shortcut(for: action)
    }

    private var isRecording: Bool {
        recorder.recordingAction == action
    }

    private var fieldText: String {
        if isRecording {
            return recorder.hint ?? "Press shortcut…"
        }
        return combo.map(KeyComboFormatter.string(for:)) ?? "Record Shortcut"
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if let status = model.failedRegistrations[action] {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("macOS did not accept this shortcut (error \(status)), so it does nothing. Record a different one.")
                        .accessibilityLabel("Shortcut not accepted by macOS")
                }

                Button {
                    recorder.toggle(for: action) { combo in
                        model.setShortcut(combo, for: action)
                    }
                } label: {
                    Text(fieldText)
                        .foregroundStyle(combo == nil && !isRecording ? .secondary : .primary)
                        .frame(width: 120)
                }
                .tint(isRecording ? .accentColor : nil)
                .help(isRecording ? "Press the new shortcut. ⌫ removes it, ⎋ cancels." : "Click to record a shortcut")

                Button {
                    recorder.cancel()
                    model.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(combo == nil ? 0 : 1)
                .disabled(combo == nil)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut for \(action.title)")
            }
        } label: {
            Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.symbolName)
                    .frame(width: 20)
            }
        }
    }
}
