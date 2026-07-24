import Foundation
import os

let markerLog = Logger(subsystem: "dev.looseconfetti.marker", category: "watcher")

/// Diagnostic trail that survives on machines where nobody runs `log show`:
/// appends to ~/Library/Logs/Marker.log so a repro can be reported by
/// copying one file. Mirror into the unified log too so live streaming
/// keeps working. Keep this on the click-paste path only — it's a debug
/// aid, not a general logger. The file half is gated by the
/// "diagLogEnabled" setting (off by default); the unified-log half always
/// runs.
func diagLog(_ message: String) {
    markerLog.info("\(message, privacy: .public)")
    DiagFile.shared.append(message)
}

final class DiagFile {
    static let shared = DiagFile()

    var enabled = UserDefaults.standard.bool(forKey: "diagLogEnabled")

    private let queue = DispatchQueue(label: "dev.looseconfetti.marker.diaglog")
    private let url = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Marker.log")
    private let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func append(_ message: String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async { [url] in
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                // 5 MB cap: start over rather than grow unbounded.
                if let size = try? handle.seekToEnd(), size > 5_000_000 {
                    try? handle.truncate(atOffset: 0)
                }
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
