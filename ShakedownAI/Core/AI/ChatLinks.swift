import Foundation
import SwiftUI

/// In-chat entity links. Both AI providers emit lightweight tokens —
/// `[[show:1977-05-08|Cornell 5/8/77]]`, `[[song:dark star|Dark Star]]`,
/// `[[era:brent|The Brent Years]]` — which render as tappable links that
/// navigate to the matching screen. Show tokens also become playable cards
/// under the reply once the archive confirms a tape exists.
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

    /// Object-replacement character: stands in for each token while the
    /// surrounding prose goes through the markdown parser, then is swapped
    /// for the styled link. Parsing once (rather than per segment) keeps
    /// emphasis that straddles a token intact.
    private static let placeholder: Character = "\u{FFFC}"

    /// Parses tokens into an AttributedString with tappable, styled links.
    /// Inline markdown in the prose (`**bold**`, `_italic_`) renders as
    /// styling rather than literal asterisks; block syntax (`1. `, `- `,
    /// `#`, `>`) is left as typed so "Scarlet > Fire" survives.
    static func render(_ text: String, linkColor: Color) -> AttributedString {
        var links: [(kind: String, value: String, label: String)] = []
        let cleaned = text.replacingOccurrences(of: String(placeholder), with: "")
        let replaced = cleaned.replacing(tokenPattern) { match in
            links.append((
                kind: String(match.output.1),
                value: String(match.output.2).trimmingCharacters(in: .whitespaces),
                label: String(match.output.3)
            ))
            return String(placeholder)
        }

        var result = inlineMarkdown(replaced)
        var pending = links[...]
        while let index = result.characters.firstIndex(of: placeholder),
              let link = pending.popFirst() {
            var linkText = AttributedString(link.label)
            if let url = url(kind: link.kind, value: link.value) {
                linkText.link = url
                linkText.foregroundColor = linkColor
                linkText.underlineStyle = .single
            }
            result.replaceSubrange(index..<result.characters.index(after: index), with: linkText)
        }
        return result
    }

    /// Inline-only markdown, falling back to the raw text if the parser balks.
    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Inline segments

    /// A reply split around the shows that earned a card: prose runs and
    /// cards interleave in reading order, so a card sits exactly where the
    /// model named the show instead of piling up under the reply.
    enum Segment: Equatable {
        case text(String)
        /// A card for `date`, with the model's one-line reason when the token
        /// was followed by one ("[[show:…|…]] — the Dark Star that…").
        case show(date: String, note: String?)
    }

    /// Splits `text` into segments. Only dates in `cardDates` become cards,
    /// and only on their first mention — later mentions stay inline links.
    /// A token that opens its line is a list item: the reason after it (up
    /// to the end of the line, introduced by a dash or colon) travels with
    /// the card. A token mid-sentence becomes a card in the flow, keeping
    /// only a short dash aside as its note; otherwise the punctuation that
    /// glued it to the sentence is dropped so the prose picks up cleanly
    /// beneath it. Blank lines around cards are absorbed.
    static func segments(in text: String, cardDates: Set<String>) -> [Segment] {
        var segments: [Segment] = []
        var pendingText = ""
        var used = Set<String>()
        var remainder = Substring(text)

        func flushText() {
            let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { segments.append(.text(trimmed)) }
            pendingText = ""
        }

        while let match = remainder.firstMatch(of: tokenPattern) {
            let kind = String(match.output.1)
            let date = String(match.output.2).trimmingCharacters(in: .whitespaces)
            let before = remainder[remainder.startIndex..<match.range.lowerBound]
            guard kind == "show", cardDates.contains(date), used.insert(date).inserted else {
                pendingText += before + match.output.0
                remainder = remainder[match.range.upperBound...]
                continue
            }
            pendingText += before
            let opensLine = pendingText.lastLineIsBlank
            flushText()
            var after = remainder[match.range.upperBound...]
            let note = takeNote(from: &after, allowLongLine: opensLine)
            if note == nil { dropJoiningPunctuation(from: &after) }
            segments.append(.show(date: date, note: note))
            remainder = after
        }
        pendingText += remainder
        flushText()
        return segments
    }

    /// " — the Dark Star that goes weightless.\n" → "the Dark Star that goes
    /// weightless.", consuming it (and the line break) from `rest`. A line
    /// that goes on to mention another show is prose, not a note. A token
    /// that opened its line is a list item and may carry a long note; one
    /// dropped mid-sentence only keeps a short aside, so a whole paragraph
    /// never disappears into a card.
    private static let midLineNoteLimit = 160

    private static func takeNote(from rest: inout Substring, allowLongLine: Bool) -> String? {
        let line = rest.prefix { $0 != "\n" }
        let trimmed = line.drop { $0 == " " }
        guard let lead = trimmed.first, "—–-:".contains(lead), !line.contains("[["),
              allowLongLine || line.count <= midLineNoteLimit else { return nil }
        let note = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        rest = rest[line.endIndex...]
        return note.isEmpty ? nil : note
    }

    /// Eats the ": ", " — ", ", " or "." that tied a mid-sentence token to
    /// what follows, without crossing a line break.
    private static func dropJoiningPunctuation(from rest: inout Substring) {
        rest = rest.drop { $0 == " " || ".,;:—–-".contains($0) }
    }

    /// Strips tokens down to their labels (for persistence-agnostic plain text).
    static func plainText(_ text: String) -> String {
        text.replacing(tokenPattern) { match in String(match.output.3) }
    }

    // MARK: - Dates

    /// "5/8/77", "1977-05-08", "1977-5-8" → "1977-05-08". Accepts anything in
    /// the band's 1965–95 span; returns unique dates in ascending order.
    static func isoDates(in text: String) -> [String] {
        var dates: [String] = []
        let iso = /\b(19[6-9]\d)-(\d{1,2})-(\d{1,2})\b/
        for match in text.matches(of: iso) {
            if let m = Int(match.2), let d = Int(match.3), (1...12).contains(m), (1...31).contains(d) {
                dates.append(String(format: "%@-%02d-%02d", String(match.1), m, d))
            }
        }
        let slashes = /\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b/
        for match in text.matches(of: slashes) {
            guard let m = Int(match.1), let d = Int(match.2), var y = Int(match.3),
                  (1...12).contains(m), (1...31).contains(d) else { continue }
            if y < 100 { y += 1900 }
            if (1965...1995).contains(y) {
                dates.append(String(format: "%04d-%02d-%02d", y, m, d))
            }
        }
        return Array(Set(dates)).sorted()
    }

    /// Guard rail for smaller models: show tokens whose value is a date in
    /// some other spelling ("5/8/77", "1977-5-8") are rewritten to ISO so the
    /// archive lookup and the card resolution both key on the same string.
    /// Values that don't parse as exactly one date are left untouched.
    static func normalizingShowDates(_ text: String) -> String {
        text.replacing(tokenPattern) { match in
            let kind = String(match.output.1)
            let value = String(match.output.2).trimmingCharacters(in: .whitespaces)
            guard kind == "show" else { return String(match.output.0) }
            let parsed = isoDates(in: value)
            guard parsed.count == 1, let iso = parsed.first else { return String(match.output.0) }
            return "[[show:\(iso)|\(match.output.3)]]"
        }
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

    /// A verified reply: the rewritten text plus the tapes worth a card.
    struct ShowVerification: Sendable, Equatable {
        var text: String
        var shows: [Show]
    }

    /// One pass over a reply: `lookups` maps each show date to the archive's
    /// recordings for it (best first). Text is rewritten as in
    /// `verifyShowTokens`; every confirmed date contributes its best tape as
    /// a card, in order of first mention, capped at `maxAttachments`. Dates
    /// missing from `lookups` (a failed lookup) keep their link and get no
    /// card rather than being declared missing.
    static func verifyShows(in text: String, lookups: [String: [Show]], maxAttachments: Int = 6) -> ShowVerification {
        let availability = lookups.mapValues { !$0.isEmpty }
        var shows: [Show] = []
        for date in showDates(in: text) {
            guard shows.count < maxAttachments, let best = lookups[date]?.first else { continue }
            shows.append(best)
        }
        return ShowVerification(text: verifyShowTokens(text, availability: availability), shows: shows)
    }
}

nonisolated private extension String {
    /// True when nothing but whitespace follows the last line break.
    var lastLineIsBlank: Bool {
        let tail = self.lastIndex(of: "\n").map { self[self.index(after: $0)...] } ?? self[...]
        return tail.allSatisfy(\.isWhitespace)
    }
}
