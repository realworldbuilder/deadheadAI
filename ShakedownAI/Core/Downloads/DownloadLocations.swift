import Foundation

/// Pure path planning for downloaded audio. Files live at
/// `Application Support/Downloads/{identifier}/{encodedFileName}`; archive file
/// names are percent-encoded for the on-disk name so a `/` inside an item's
/// file name can never escape the show directory.
nonisolated enum DownloadLocations {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    static func showDirectory(identifier: String) -> URL {
        root.appending(path: encode(identifier), directoryHint: .isDirectory)
    }

    static func fileURL(identifier: String, fileName: String) -> URL {
        showDirectory(identifier: identifier).appending(path: encode(fileName), directoryHint: .notDirectory)
    }

    /// Index/record key for one downloaded track.
    static func trackKey(identifier: String, fileName: String) -> String {
        identifier + "|" + fileName
    }

    /// URLSessionTask.taskDescription payload. Archive identifiers never
    /// contain `|` (they're [A-Za-z0-9._-]), so splitting on the first pipe is
    /// unambiguous even if a file name contains one.
    static func makeTaskDescription(identifier: String, fileName: String) -> String {
        trackKey(identifier: identifier, fileName: fileName)
    }

    static func parseTaskDescription(_ description: String) -> (identifier: String, fileName: String)? {
        guard let pipe = description.firstIndex(of: "|") else { return nil }
        let identifier = String(description[..<pipe])
        let fileName = String(description[description.index(after: pipe)...])
        guard !identifier.isEmpty, !fileName.isEmpty else { return nil }
        return (identifier, fileName)
    }

    /// Downloads are re-fetchable from the archive; keep them out of iCloud backups.
    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    // MARK: - Encoding

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: ".-_ ()'")
        return set
    }()

    /// Deterministic filesystem-safe encoding. Encodes `%` itself (it's not in
    /// the allowed set), so distinct inputs can't collide.
    static func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
