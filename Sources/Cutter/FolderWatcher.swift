import Foundation

/// Tells when something is added to, removed from or renamed in a folder.
///
/// The screenshots panel uses it while it is open: with the corner preview on, macOS
/// writes a screenshot to disk only when the preview has gone, seconds after it was
/// taken, and that can be after the panel has read the folder.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// Changes come in bursts (a hidden file is written, then renamed), so the report
    /// waits until the folder has been quiet for `delay`. `onChange` runs on the main queue.
    init?(folder: URL, delay: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.pending?.cancel()
            let report = DispatchWorkItem(block: onChange)
            self.pending = report
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: report)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
