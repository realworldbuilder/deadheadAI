import Foundation
import SwiftUI

/// In-chat entity links. Both AI providers emit lightweight tokens —
/// `[[show:1977-05-08|Cornell 5/8/77]]`, `[[song:dark star|Dark Star]]`,
/// `[[era:brent|The Brent Years]]` — which render as tappable links that
/// navigate to the matching screen.
nonisolated enum ChatLink {

    enum Destination: Hashable {
        case show(date: String)
        case song(key: String)
        case era(id: String)
    }

    static let scheme = "deadheads"

    static func url(kind: String, value: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = kind
        components.queryItems = [URLQueryItem(name: "v", value: value)]
        return components.url
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme == scheme,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "v" })?.value
        else { return nil }
        switch url.host() {
        case "show": return .show(date: value)
        case "song": return .song(key: value)
        case "era": return .era(id: value)
        default: return nil
        }
    }

    /// Token helpers for providers composing replies.
    static func show(_ date: String, label: String) -> String { "[[show:\(date)|\(label)]]" }
    static func song(_ key: String, label: String) -> String { "[[song:\(key)|\(label)]]" }
    static func era(_ id: String, label: String) -> String { "[[era:\(id)|\(label)]]" }

    // MARK: - Rendering

    // Regex isn't Sendable, so build it per call (cheap).
    private static var tokenPattern: Regex<(Substring, Substring, Substring, Substring)> {
        /\[\[(show|song|era):([^|\]]+)\|([^\]]+)\]\]/
    }

    /// Parses tokens into an AttributedString with tappable, styled links.
    static func render(_ text: String, linkColor: Color) -> AttributedString {
        var result = AttributedString()
        var remainder = Substring(text)
        while let match = remainder.firstMatch(of: tokenPattern) {
            result += AttributedString(String(remainder[remainder.startIndex..<match.range.lowerBound]))
            let kind = String(match.output.1)
            let value = String(match.output.2).trimmingCharacters(in: .whitespaces)
            let label = String(match.output.3)
            var linkText = AttributedString(label)
            if let url = url(kind: kind, value: value) {
                linkText.link = url
                linkText.foregroundColor = linkColor
                linkText.underlineStyle = .single
            }
            result += linkText
            remainder = remainder[match.range.upperBound...]
        }
        result += AttributedString(String(remainder))
        return result
    }

    /// Strips tokens down to their labels (for persistence-agnostic plain text).
    static func plainText(_ text: String) -> String {
        text.replacing(tokenPattern) { match in String(match.output.3) }
    }

    // MARK: - Archive verification

    /// Unique show dates referenced by tokens in the text.
    static func showDates(in text: String) -> [String] {
        var seen = Set<String>()
        var dates: [String] = []
        for match in text.matches(of: tokenPattern) where match.output.1 == "show" {
            let date = String(match.output.2).trimmingCharacters(in: .whitespaces)
            if seen.insert(date).inserted { dates.append(date) }
        }
        return dates
    }

    /// Rewrites show tokens based on archive availability: confirmed shows get
    /// a ▶ play marker; missing ones lose the link and say so plainly.
    /// Dates absent from the map are left untouched (verification failed).
    static func verifyShowTokens(_ text: String, availability: [String: Bool]) -> String {
        text.replacing(tokenPattern) { match in
            let kind = String(match.output.1)
            let value = String(match.output.2).trimmingCharacters(in: .whitespaces)
            let label = String(match.output.3)
            guard kind == "show", let available = availability[value] else {
                return String(match.output.0)
            }
            if available {
                // U+FE0E keeps the triangle as text so it inherits link color.
                // Compare by scalar: "▶" and "▶︎" are distinct grapheme clusters.
                let alreadyMarked = label.unicodeScalars.first == "▶"
                let marked = alreadyMarked ? label : "▶\u{FE0E} " + label
                return "[[show:\(value)|\(marked)]]"
            }
            return "\(label) (no tape in the archive for this one)"
        }
    }
}
