import Foundation

/// Lays a recording's tracks out as one list shaped by the catalog setlist:
/// set headings where the sets break, segue markers on the matched tracks,
/// and setlist songs the tape doesn't carry sitting dimmed in their spot.
///
/// The tracks are the rows — every file on the tape appears exactly once, in
/// tape order, so tuning and crowd tracks stay reachable. Without a setlist
/// the layout degrades to a plain numbered track list.
nonisolated enum TapeSetlist {

    enum Row: Hashable, Sendable, Identifiable {
        /// "Set 1", "Set 2", "Encore" — from the catalog's set labels.
        case heading(String)
        /// A file on the tape, by index into the recording's tracks.
        case track(index: Int, seguesIntoNext: Bool)
        /// A setlist song the tape doesn't carry.
        case missing(SetlistEntry)

        var id: String {
            switch self {
            case .heading(let label): "h:\(label)"
            case .track(let index, _): "t:\(index)"
            case .missing(let entry): "m:\(entry.position)"
            }
        }

        var isHeading: Bool {
            if case .heading = self { return true }
            return false
        }

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }
    }

    static func rows(setlist: Setlist?, tracks: [Track],
                     aliases: [String: String] = [:]) -> [Row] {
        guard let setlist, !setlist.sets.isEmpty else {
            return tracks.indices.map { .track(index: $0, seguesIntoNext: false) }
        }

        let matched = SetlistMatcher.align(setlist.sets.flatMap(\.entries), with: tracks,
                                           aliases: aliases)
        let indexByPosition = Dictionary(uniqueKeysWithValues: matched.map { ($0.entry.position, $0.trackIndex) })

        var rows: [Row] = []
        var cursor = 0
        // Track index → row position, so a combined file that satisfies two
        // consecutive setlist songs can pick up the second song's segue flag.
        var rowForTrack: [Int: Int] = [:]

        func emit(_ index: Int, segues: Bool) {
            if let row = rowForTrack[index] {
                if segues, case .track(let i, false) = rows[row] {
                    rows[row] = .track(index: i, seguesIntoNext: true)
                }
                return
            }
            rowForTrack[index] = rows.count
            rows.append(.track(index: index, seguesIntoNext: segues))
        }

        for set in setlist.sets {
            rows.append(.heading(set.label))
            for entry in set.entries {
                guard let trackIndex = indexByPosition[entry.position] ?? nil else {
                    rows.append(.missing(entry))
                    continue
                }
                while cursor < trackIndex {
                    emit(cursor, segues: false)
                    cursor += 1
                }
                emit(trackIndex, segues: entry.seguesIntoNext)
                cursor = max(cursor, trackIndex + 1)
            }
        }
        while cursor < tracks.count {
            emit(cursor, segues: false)
            cursor += 1
        }
        return rows
    }
}
