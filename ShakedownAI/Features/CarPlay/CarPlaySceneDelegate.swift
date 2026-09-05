#if canImport(CarPlay)
import CarPlay
import Foundation

// CarPlay audio app: Runs first — the stretch of tape you can plan a drive
// around, each row wearing its running time — then Downloads (the road-trip
// case needs no network), Recent, and On This Day. Now Playing comes free
// via the existing MPNowPlayingInfoCenter wiring.
//
// ⚠️ Dormant until Apple grants the CarPlay audio entitlement
// (developer.apple.com/carplay). To enable, add to project.yml (verified
// 2026-09-05: with these the app appears on the Simulator's CarPlay home —
// but only in a *signed* build; CODE_SIGNING_ALLOWED=NO drops entitlements):
//
//   entitlements.properties:
//     com.apple.developer.carplay-audio: true
//   info.properties:
//     UIApplicationSceneManifest:
//       UIApplicationSupportsMultipleScenes: true
//       UISceneConfigurations:
//         CPTemplateApplicationSceneSessionRoleApplication:
//           - UISceneConfigurationName: CarPlay
//             UISceneClassName: CPTemplateApplicationScene
//             UISceneDelegateClassName: $(PRODUCT_MODULE_NAME).CarPlaySceneDelegate
//
// then xcodegen generate. The SwiftUI phone scene keeps working alongside.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    /// The home shelf's runs, kept alive so rows can play from the pinned tape.
    private var shelf: RunShelfModel?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let tabs = CPTabBarTemplate(templates: [runsTemplate(), downloadsTemplate(), recentTemplate(), onThisDayTemplate()])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    // MARK: - Runs

    /// Two sections: runs already on the device (instant, no network — the
    /// drive-through-nowhere case) and today's shelf from the home page,
    /// filled in as the archive pins each run to a tape. Every row is
    /// "Scarlet Begonias > Fire on the Mountain / 5/8/77 · Barton Hall · 26 min".
    private func runsTemplate() -> CPListTemplate {
        let list = CPListTemplate(title: "Jams", sections: [])
        list.tabImage = UIImage(systemName: "flame")
        list.emptyViewTitleVariants = ["Finding tonight's jams…"]
        list.emptyViewSubtitleVariants = ["Segues and long versions, ready to play on their own."]
        Task { @MainActor [weak self, weak list] in
            guard let self, let env = AppEnvironment.current, let list else { return }
            let offline = await OfflineRuns.onDevice(env: env)
            list.updateSections(self.runSections(offline: offline, shelf: nil))

            let shelf = self.shelf ?? RunShelfModel(env: env)
            self.shelf = shelf
            await shelf.load()
            list.updateSections(self.runSections(offline: offline, shelf: shelf))
            list.emptyViewTitleVariants = ["No jams yet"]
            list.emptyViewSubtitleVariants = ["Download a show in Nethead, or connect to the internet."]
        }
        return list
    }

    private func runSections(offline: [ResolvedRun], shelf: RunShelfModel?) -> [CPListSection] {
        var sections: [CPListSection] = []

        let deviceRows = RunRows.onDevice(offline)
        if !deviceRows.isEmpty {
            let queues = [offline.flatMap(\.entries)] + offline.map(\.entries)
            let items = zip(deviceRows, queues).map { row, entries in
                playableItem(title: row.title, subtitle: row.detail, entries: entries)
            }
            sections.append(CPListSection(items: items, header: "On this device", sectionIndexTitle: nil))
        }

        if let shelf {
            let reachable = shelf.picks.filter { !shelf.unavailable.contains($0.id) }
            let rows = RunRows.shelf(
                picks: reachable.map { ($0.run, $0.venue, shelf.lengthText(for: $0)) },
                totalLengthText: shelf.totalLengthText)
            guard let stitchRow = rows.first else { return sections }
            let stitch = CPListItem(text: stitchRow.title, detailText: stitchRow.detail)
            stitch.handler = { [weak shelf] _, completion in
                Task { @MainActor in
                    await shelf?.playAll()
                    completion()
                }
            }
            var items = [stitch]
            for (row, pick) in zip(rows.dropFirst(), reachable) {
                let item = CPListItem(text: row.title, detailText: row.detail)
                item.handler = { [weak shelf] _, completion in
                    Task { @MainActor in
                        await shelf?.play(pick)
                        completion()
                    }
                }
                items.append(item)
            }
            sections.append(CPListSection(items: items, header: "Today's shelf", sectionIndexTitle: nil))
        }
        return sections
    }

    // MARK: - Tabs

    private func downloadsTemplate() -> CPListTemplate {
        var items: [CPListItem] = []
        if let env = AppEnvironment.current {
            for record in env.downloads.store.allRecords() {
                guard let show = env.downloads.store.showSnapshot(for: record.identifier),
                      let detail = env.downloads.store.detailSnapshot(for: record.identifier) else { continue }
                items.append(playableItem(title: show.displayDate,
                                          subtitle: show.venue ?? "",
                                          show: show, tracks: detail.tracks))
            }
        }
        let list = CPListTemplate(title: "Downloads", sections: [CPListSection(items: items)])
        list.tabImage = UIImage(systemName: "arrow.down.circle")
        list.emptyViewTitleVariants = ["No downloads yet"]
        list.emptyViewSubtitleVariants = ["Download shows in Nethead for offline drives."]
        return list
    }

    private func recentTemplate() -> CPListTemplate {
        var items: [CPListItem] = []
        if let env = AppEnvironment.current {
            for recent in env.history.recentShows(limit: 10) {
                let item = CPListItem(text: recent.displayName, detailText: nil)
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.playIdentifier(recent.identifier)
                        completion()
                    }
                }
                items.append(item)
            }
        }
        let list = CPListTemplate(title: "Recent", sections: [CPListSection(items: items)])
        list.tabImage = UIImage(systemName: "clock")
        list.emptyViewTitleVariants = ["Nothing played yet"]
        return list
    }

    private func onThisDayTemplate() -> CPListTemplate {
        let list = CPListTemplate(title: "On This Day", sections: [])
        list.tabImage = UIImage(systemName: "calendar")
        list.emptyViewTitleVariants = ["Loading…"]
        Task { @MainActor [weak self, weak list] in
            guard let env = AppEnvironment.current, let list else { return }
            let monthDay = HomeModel.monthDayString(.now)
            let shows = (try? await env.recordingProvider.onThisDay(monthDay: monthDay)) ?? []
            var items: [CPListItem] = []
            for show in shows.prefix(20) {
                let item = CPListItem(text: show.displayDate, detailText: show.venue)
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.playIdentifier(show.identifier, show: show)
                        completion()
                    }
                }
                items.append(item)
            }
            list.updateSections([CPListSection(items: items)])
            list.emptyViewTitleVariants = ["No shows on this date"]
        }
        return list
    }

    // MARK: - Playback

    private func playableItem(title: String, subtitle: String,
                              show: Show, tracks: [Track]) -> CPListItem {
        playableItem(title: title, subtitle: subtitle,
                     entries: tracks.map { PlayerQueueEntry(show: show, track: $0) })
    }

    private func playableItem(title: String, subtitle: String, entries: [PlayerQueueEntry]) -> CPListItem {
        let item = CPListItem(text: title, detailText: subtitle)
        item.handler = { _, completion in
            Task { @MainActor in
                AppEnvironment.current?.playerEngine.play(entries: entries)
                completion()
            }
        }
        return item
    }

    private func playIdentifier(_ identifier: String, show: Show? = nil) async {
        guard let env = AppEnvironment.current else { return }
        guard let detail = try? await env.metadataProvider.detail(for: identifier),
              !detail.tracks.isEmpty else { return }
        let resolvedShow = show
            ?? env.downloads.store.showSnapshot(for: identifier)
            ?? Show(identifier: identifier, title: detail.title ?? identifier,
                    date: nil, dateString: detail.dateString, venue: detail.venue,
                    location: detail.location, year: nil, avgRating: nil,
                    numReviews: nil, downloads: nil, source: detail.source)
        env.playerEngine.play(show: resolvedShow, tracks: detail.tracks)
    }
}
#endif
