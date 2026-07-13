import Foundation

/// A plain description of the app a selection came from, so the domain
/// layer never touches NSRunningApplication.
struct SourceApp: Equatable {
    let pid: pid_t
    let bundleID: String
    let name: String
    let isSelf: Bool
}