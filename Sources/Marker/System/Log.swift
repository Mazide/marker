import Foundation
import os

let markerLog = Logger(subsystem: "dev.looseconfetti.marker", category: "watcher")

/// Records a privacy-safe diagnostic event in both the unified log and the
/// optional on-disk trail. Callers must pass decisions and metadata only; never
/// clipboard or selection contents.
func diagLog(_ message: String) {
    markerLog.info("\(message, privacy: .public)")
    DiagFile.shared.append(message)
}

struct DiagnosticLogMetadata: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let architecture: String

    init(
        appVersion: String,
        appBuild: String,
        operatingSystem: String,
        architecture: String
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }

    static func current() -> DiagnosticLogMetadata {
        let info = Bundle.main.infoDictionary
        return DiagnosticLogMetadata(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: info?["CFBundleVersion"] as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

enum DiagnosticLogError: LocalizedError {
    case enableFailed(String)
    case sessionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case let .enableFailed(reason):
            "Could not enable the diagnostic log: \(reason)"
        case let .sessionFailed(reason):
            "Could not start a diagnostic session: \(reason)"
        case let .exportFailed(reason):
            "Could not export the diagnostic log: \(reason)"
        }
    }
}

/// A small, private, ordered diagnostic trail for reproductions performed
/// without a debugger. The live file and one rotated predecessor are retained.
final class DiagFile {
    static let shared = DiagFile()

    var enabled: Bool {
        get { onQueue { isEnabled } }
        set {
            do {
                try setEnabled(newValue)
            } catch {
                markerLog.error(
                    "Failed to change diagnostic log state: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    var fileURL: URL { url }

    var lastErrorDescription: String? {
        onQueue { lastError?.localizedDescription }
    }

    private struct Session {
        let id: UUID
        let startedAt: Date
    }

    private static let defaultMaximumFileSize: UInt64 = 5_000_000
    private static let maximumMessageLength = 4_096

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let url: URL
    private let previousURL: URL
    private let maximumFileSize: UInt64
    private let now: () -> Date
    private let sessionID: () -> UUID
    private let metadata: DiagnosticLogMetadata
    private let fileManager: FileManager
    private let stamp: ISO8601DateFormatter

    private var isEnabled: Bool
    private var session: Session?
    private var lastError: Error?

    convenience init() {
        let logURL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Marker.log")
        self.init(
            fileURL: logURL,
            enabled: UserDefaults.standard.bool(forKey: "diagLogEnabled")
        )
    }

    init(
        fileURL: URL,
        enabled: Bool = false,
        maximumFileSize: UInt64 = DiagFile.defaultMaximumFileSize,
        now: @escaping () -> Date = Date.init,
        sessionID: @escaping () -> UUID = UUID.init,
        metadata: DiagnosticLogMetadata = .current(),
        fileManager: FileManager = .default
    ) {
        url = fileURL
        previousURL = Self.rotatedURL(for: fileURL)
        self.maximumFileSize = maximumFileSize
        self.now = now
        self.sessionID = sessionID
        self.metadata = metadata
        self.fileManager = fileManager
        isEnabled = enabled
        queue = DispatchQueue(label: "dev.looseconfetti.marker.diaglog.\(UUID().uuidString)")
        stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        queue.setSpecific(key: queueKey, value: 1)

        // Harden logs created by older Marker builds even while recording is
        // currently disabled. This changes permissions only; no file is made.
        for existingURL in [url, previousURL]
            where fileManager.fileExists(atPath: existingURL.path) {
            try? makePrivate(existingURL)
        }
    }

    /// Changes recording state. Enabling eagerly creates a private file and a
    /// session header so setup errors can be shown before a reproduction starts.
    func setEnabled(_ enabled: Bool) throws {
        do {
            try onQueue {
                if !enabled {
                    isEnabled = false
                    session = nil
                    return
                }

                isEnabled = true
                do {
                    try ensureSessionStarted()
                    lastError = nil
                } catch {
                    isEnabled = false
                    session = nil
                    throw error
                }
            }
        } catch {
            let wrapped = DiagnosticLogError.enableFailed(error.localizedDescription)
            onQueue { lastError = wrapped }
            throw wrapped
        }
    }

    /// Ensures that the current process has a session header. This is a no-op
    /// while recording is disabled.
    func beginSession() throws {
        do {
            try onQueue {
                guard isEnabled else { return }
                try ensureSessionStarted()
                lastError = nil
            }
        } catch {
            let wrapped = DiagnosticLogError.sessionFailed(error.localizedDescription)
            onQueue { lastError = wrapped }
            throw wrapped
        }
    }

    /// Queues one single-line record. Pending records are serialized with
    /// enable, session, rotation, and export operations.
    func append(_ message: String) {
        queue.async { [self] in
            guard isEnabled else { return }
            do {
                try ensureSessionStarted()
                let line = "\(timestamp(now())) \(sanitize(message))\n"
                try append(Data(line.utf8))
                lastError = nil
            } catch {
                lastError = error
                markerLog.error(
                    "Failed to write diagnostic log: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    /// Waits for all records submitted before this call to be persisted.
    func flush() throws {
        do {
            try onQueue {
                guard isEnabled else { return }
                try ensureSessionStarted()
            }
        } catch {
            let wrapped = DiagnosticLogError.sessionFailed(error.localizedDescription)
            onQueue { lastError = wrapped }
            throw wrapped
        }
    }

    /// Produces one self-contained text file. It includes the rotated tail (if
    /// present), the current trail, and fresh export metadata. Entering this
    /// serial queue also flushes every append submitted before the export.
    func export(to destination: URL, snapshot: String? = nil) throws {
        do {
            try onQueue {
                guard destination.standardizedFileURL != url.standardizedFileURL,
                      destination.standardizedFileURL != previousURL.standardizedFileURL
                else {
                    throw CocoaError(.fileWriteFileExists)
                }

                if isEnabled {
                    try ensureSessionStarted()
                }

                var output = Data(exportHeader().utf8)
                if let snapshot {
                    output.append(Data("\n# section=export_snapshot\n\(sanitize(snapshot))\n".utf8))
                }
                var foundTrail = false
                for (label, source) in [("previous", previousURL), ("current", url)] {
                    guard fileManager.fileExists(atPath: source.path) else { continue }
                    foundTrail = true
                    output.append(Data("\n# section=\(label)\n".utf8))
                    output.append(try Data(contentsOf: source))
                    if output.last != 0x0A {
                        output.append(Data("\n".utf8))
                    }
                }
                if !foundTrail {
                    output.append(Data("\n# log_state=no_recorded_events\n".utf8))
                }

                let parent = destination.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try output.write(to: destination, options: .atomic)
                try makePrivate(destination)
                lastError = nil
            }
        } catch {
            let wrapped = DiagnosticLogError.exportFailed(error.localizedDescription)
            onQueue { lastError = wrapped }
            throw wrapped
        }
    }

    private func ensureSessionStarted() throws {
        guard session == nil else { return }
        try ensureLogDirectory()
        let newSession = Session(id: sessionID(), startedAt: now())
        try append(Data(sessionHeader(newSession, continued: false).utf8))
        session = newSession
    }

    private func append(_ data: Data) throws {
        try ensureLogDirectory()
        let currentSize = fileSize(at: url)
        if currentSize > 0,
           currentSize + UInt64(data.count) > maximumFileSize {
            try rotateCurrentFile()
            if let session {
                try appendDirect(Data(sessionHeader(session, continued: true).utf8))
            }
        }
        try appendDirect(data)
    }

    private func appendDirect(_ data: Data) throws {
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try makePrivate(url)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func rotateCurrentFile() throws {
        if fileManager.fileExists(atPath: previousURL.path) {
            try fileManager.removeItem(at: previousURL)
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.moveItem(at: url, to: previousURL)
            try makePrivate(previousURL)
        }
    }

    private func ensureLogDirectory() throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func makePrivate(_ target: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: target.path
        )
    }

    private func fileSize(at target: URL) -> UInt64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: target.path),
              let value = attributes[.size] as? NSNumber
        else { return 0 }
        return value.uint64Value
    }

    private func sessionHeader(_ session: Session, continued: Bool) -> String {
        """
        # Marker diagnostic log
        # format=1
        # session=\(session.id.uuidString)
        # started=\(timestamp(session.startedAt))
        # app_version=\(sanitize(metadata.appVersion))
        # app_build=\(sanitize(metadata.appBuild))
        # macOS=\(sanitize(metadata.operatingSystem))
        # architecture=\(sanitize(metadata.architecture))
        # continued_after_rotation=\(continued)
        # timestamps=UTC
        # privacy=Clipboard and selection contents are not recorded.

        """
    }

    private func exportHeader() -> String {
        """
        # Marker diagnostic export
        # format=1
        # exported=\(timestamp(now()))
        # app_version=\(sanitize(metadata.appVersion))
        # app_build=\(sanitize(metadata.appBuild))
        # macOS=\(sanitize(metadata.operatingSystem))
        # architecture=\(sanitize(metadata.architecture))
        # recording_enabled=\(isEnabled)
        # recorder_error=\(lastError.map { sanitize($0.localizedDescription) } ?? "none")
        # timestamps=UTC
        # privacy=Clipboard and selection contents are not recorded.
        # reading_hint=Look for outcome=rejected, reason=..., *.failed, or domain.error.
        """
    }

    private func timestamp(_ date: Date) -> String {
        stamp.string(from: date)
    }

    private func sanitize(_ value: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let redacted = homePath.isEmpty
            ? value
            : value.replacingOccurrences(of: homePath, with: "<home>")
        var output = ""
        output.reserveCapacity(min(redacted.count, Self.maximumMessageLength))
        var count = 0
        for scalar in redacted.unicodeScalars {
            guard count < Self.maximumMessageLength else { break }
            switch scalar.value {
            case 0x0A:
                output.append("\\n")
            case 0x0D:
                output.append("\\r")
            case 0x09:
                output.append(" ")
            case 0x00 ... 0x1F, 0x7F:
                output.append("�")
            default:
                output.unicodeScalars.append(scalar)
            }
            count += 1
        }
        return output.isEmpty ? "<empty>" : output
    }

    private func onQueue<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try operation()
        }
        return try queue.sync(execute: operation)
    }

    private static func rotatedURL(for url: URL) -> URL {
        if url.pathExtension.isEmpty {
            return url.appendingPathExtension("previous")
        }
        return url.deletingPathExtension()
            .appendingPathExtension("previous")
            .appendingPathExtension(url.pathExtension)
    }
}
