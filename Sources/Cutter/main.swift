import AppKit

if let exitCode = CommandLineTool.run(Array(CommandLine.arguments.dropFirst())) {
    exit(exitCode)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Also set by LSUIElement in Info.plist; this covers running the bare binary.
app.setActivationPolicy(.accessory)
app.run()
