import AppKit
import Foundation

/// Installs the bundled marker-cli as `/usr/local/bin/marker`, VS Code
/// "install code command" style. A plain symlink first; if /usr/local/bin
/// isn't writable, one admin prompt via AppleScript. We never touch shell
/// rc files — guessing at a user's PATH config breaks more than it fixes,
/// and /usr/local/bin is on the default PATH everywhere.
@MainActor
enum CLIInstaller {
    static let linkPath = "/usr/local/bin/marker"

    static var bundledCLIPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/marker-cli"
    }

    enum Status: Equatable {
        /// Symlink exists and points at a Marker bundle.
        case installed
        case missing
        /// Something else owns the path (homebrew formula, hand-rolled script).
        case foreign
    }

    static func status() -> Status {
        let fm = FileManager.default
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: linkPath) else {
            return fm.fileExists(atPath: linkPath) ? .foreign : .missing
        }
        return dest.hasSuffix("/Contents/MacOS/marker-cli") ? .installed : .foreign
    }

    @discardableResult
    static func install() -> Bool {
        let fm = FileManager.default
        do {
            try? fm.removeItem(atPath: linkPath)
            try fm.createDirectory(
                atPath: "/usr/local/bin", withIntermediateDirectories: true)
            try fm.createSymbolicLink(
                atPath: linkPath, withDestinationPath: bundledCLIPath)
            markerLog.info("cli installed at \(linkPath, privacy: .public)")
            return true
        } catch {
            return installWithPrivileges()
        }
    }

    private static func installWithPrivileges() -> Bool {
        let script = """
        do shell script "mkdir -p /usr/local/bin && ln -sf '\(bundledCLIPath)' '\(linkPath)'" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            markerLog.error("cli install failed: \(error, privacy: .public)")
            return false
        }
        markerLog.info("cli installed at \(linkPath, privacy: .public) (admin)")
        return true
    }
}
