import AppKit
import WebKit

/// WKDownload 的承接：存到下載資料夾（預設 ~/Downloads），檔名重複加序號。
@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    enum State: Equatable { case running(Double), finished, failed(String) }

    struct Status: Equatable {
        var name: String
        var state: State
        var fileURL: URL
    }

    let directory: URL
    private(set) var latest: Status?
    var onChange: ((Status?) -> Void)?

    private var reserved = Set<String>()
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    init(directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.directory = directory
    }

    func adopt(_ download: WKDownload) {
        download.delegate = self
    }

    func dismiss() {
        latest = nil
        onChange?(nil)
    }

    /// 取得不衝突的目的地：report.txt → report (1).txt → report (2).txt。檔名一律只取最後一段，避免路徑穿越。
    func uniqueDestination(for suggested: String) -> URL {
        var name = (suggested as NSString).lastPathComponent
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "download" }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var n = 0
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) || reserved.contains(candidate) {
            n += 1
            candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
        }
        reserved.insert(candidate)
        return directory.appendingPathComponent(candidate)
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = uniqueDestination(for: suggestedFilename)
        let id = ObjectIdentifier(download)
        destinations[id] = dest
        publish(Status(name: dest.lastPathComponent, state: .running(0), fileURL: dest))
        observations[id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            MainActor.assumeIsolated {
                guard let self, let dest = self.destinations[id], self.latest?.fileURL == dest else { return }
                self.publish(Status(name: dest.lastPathComponent, state: .running(fraction), fileURL: dest))
            }
        }
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let dest = destinations.removeValue(forKey: id) else { return }
        observations.removeValue(forKey: id)
        reserved.remove(dest.lastPathComponent)
        publish(Status(name: dest.lastPathComponent, state: .finished, fileURL: dest))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        guard let dest = destinations.removeValue(forKey: id) else { return }
        observations.removeValue(forKey: id)
        reserved.remove(dest.lastPathComponent)
        publish(Status(name: dest.lastPathComponent, state: .failed(error.localizedDescription), fileURL: dest))
    }

    private func publish(_ status: Status) {
        latest = status
        onChange?(status)
    }

    func revealLatest() {
        guard let status = latest else { return }
        if case .finished = status.state {
            NSWorkspace.shared.activateFileViewerSelecting([status.fileURL])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }
}
