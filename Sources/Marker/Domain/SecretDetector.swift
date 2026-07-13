import Foundation

/// Heuristics for "this selection looks like a credential". Deliberately
/// conservative: a false negative just stores a string the user selected
/// anyway, a false positive silently loses something they wanted.
enum SecretDetector {
    /// Vendor key prefixes that are unambiguous on their own.
    private static let prefixes = [
        "sk-", "sk_live_", "sk_test_", "pk_live_", "rk_live_",   // OpenAI/Anthropic/Stripe
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",   // GitHub
        "xoxb-", "xoxp-", "xoxa-", "xoxr-",                      // Slack
        "AKIA", "ASIA",                                          // AWS
        "AIza",                                                  // Google
        "glpat-",                                                // GitLab
        "npm_", "dop_v1_", "shpat_", "SG.",                      // npm/DigitalOcean/Shopify/SendGrid
    ]

    /// `api_key = …`, `password: …`, and `Authorization: Bearer …` (the
    /// scheme word sits between the colon and the token).
    private static let assignmentPattern = try? NSRegularExpression(
        pattern: #"(?i)\b(api[_-]?key|secret|password|passwd|token|authorization|private[_-]?key)\b\s*[:=]\s*(bearer\s+|basic\s+)?\S{8,}"#
    )

    private static let pemPattern = "-----BEGIN"

    static func looksSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }

        if prefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        if trimmed.contains(pemPattern) { return true }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if assignmentPattern?.firstMatch(in: trimmed, range: range) != nil { return true }

        // A long single token of key-ish characters with real entropy:
        // catches unprefixed keys, JWTs, hex secrets. Ordinary words, URLs
        // and sentences fail on whitespace, length or character mix.
        if !trimmed.contains(where: \.isWhitespace),
           trimmed.count >= 32,
           trimmed.allSatisfy({ $0.isLetter || $0.isNumber || "-_=+/.".contains($0) }),
           looksHighEntropy(trimmed) {
            return true
        }
        return false
    }

    /// Mixed case + digits, or a long hex run — a plain lowercase word or a
    /// path/URL-like string does not qualify.
    private static func looksHighEntropy(_ token: String) -> Bool {
        let hasDigit = token.contains(where: \.isNumber)
        let hasUpper = token.contains(where: { $0.isUppercase })
        let hasLower = token.contains(where: { $0.isLowercase })
        if hasDigit, hasUpper, hasLower { return true }

        let hexish = token.allSatisfy { $0.isHexDigit }
        return hexish && token.count >= 32
    }
}