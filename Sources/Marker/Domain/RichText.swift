import Foundation

/// A captured selection: plain text always, best-effort rich flavors
/// alongside. The engine's decision logic (dedupe, trimming, secrets)
/// runs on `plain`; `rtf`/`html` only ride along to the clipboard,
/// history and paste.
struct RichText: Equatable {
    /// Flavors larger than this are dropped at capture time so a single
    /// giant selection cannot bloat history or slow the clipboard.
    static let flavorByteLimit = 512 * 1024

    var plain: String
    var rtf: Data?
    var html: String?

    init(plain: String, rtf: Data? = nil, html: String? = nil) {
        self.plain = plain
        self.rtf = rtf
        self.html = html
    }

    var hasFlavors: Bool { rtf != nil || html != nil }
}
