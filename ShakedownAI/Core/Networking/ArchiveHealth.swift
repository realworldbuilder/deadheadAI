import Foundation
import Observation

/// App-wide archive.org reachability. The HTTP layer reports server-side
/// outages (503s that survive retries); while offline, a background probe
/// rechecks the archive so the banner clears itself when service returns.
/// Connection-level failures (airplane mode, bad wifi) are NOT outages —
/// screens keep their "check your connection" copy for those.
@Observable
final class ArchiveHealth {
    static let shared = ArchiveHealth()

    private(set) var isOffline = false
    private var probeTask: Task<Void, Never>?

    /// Friendly copy for error cards when the archive itself is down.
    nonisolated static let outageMessage =
        "The Internet Archive itself is temporarily offline — it's them, not you. The tapes are safe; try again in a little while."

    func reportOutage() {
        guard !isOffline else { return }
        isOffline = true
        startProbe()
    }

    func reportSuccess() {
        guard isOffline || probeTask != nil else { return }
        probeTask?.cancel()
        probeTask = nil
        isOffline = false
    }

    /// Rechecks the archive every 45s until it answers again.
    private func startProbe() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard let self, self.isOffline, !Task.isCancelled else { return }
                if await Self.archiveResponds() {
                    self.reportSuccess()
                    return
                }
            }
        }
    }

    private nonisolated static func archiveResponds() async -> Bool {
        guard let url = URL(string:
            "https://archive.org/advancedsearch.php?q=collection%3AGratefulDead&rows=0&output=json")
        else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
