import Foundation

/// The runs already sitting on the device: every downloaded show, read
/// from its stored snapshots, with the canon and the catalog's setlist
/// aligned to the actual files on disk. No network anywhere — this is what
/// CarPlay offers on a drive through nowhere.
enum OfflineRuns {
    static func onDevice(env: AppEnvironment) async -> [ResolvedRun] {
        let store = env.downloads.store
        var found: [ResolvedRun] = []
        for record in store.allRecords() where record.statusRaw == DownloadStore.ShowStatus.completed.rawValue {
            guard let show = store.showSnapshot(for: record.identifier),
                  let detail = store.detailSnapshot(for: record.identifier),
                  let date = show.dateString ?? detail.dateString else { continue }
            let night = env.catalog.isAvailable ? await env.catalog.show(onDate: date) : nil
            let setlist = env.catalog.isAvailable ? await env.catalog.setlist(forDate: date) : nil
            found += RunFinder.runs(onTape: detail.tracks, show: show,
                                    canon: env.knowledgeBase.runs(on: date),
                                    night: night, setlist: setlist, kb: env.knowledgeBase)
        }
        return found
    }
}
