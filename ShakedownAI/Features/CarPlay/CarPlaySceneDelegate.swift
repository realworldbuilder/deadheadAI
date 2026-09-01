#if canImport(CarPlay)
import CarPlay
import Foundation

// CarPlay audio app: Downloads first (the road-trip case needs no network),
// then Recent and On This Day. Now Playing comes free via the existing
// MPNowPlayingInfoCenter wiring.
//
// ⚠️ Dormant until Apple grants the CarPlay audio entitlement
// (developer.apple.com/carplay). To enable, add to project.yml:
//   com.apple.developer.carplay-audio: true   (entitlements properties)
// and the CPTemplateApplicationSceneSessionRoleApplication scene manifest
// (see README note) — then xcodegen generate.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let tabs = CPTabBarTemplate(templates: [downloadsTemplate(), recentTemplate(), onThisDayTemplate()])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
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
        list.emptyViewSubtitleVariants = ["Download shows in TapeTree for offline drives."]
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
        let item = CPListItem(text: title, detailText: subtitle)
        item.handler = { _, completion in
            Task { @MainActor in
                AppEnvironment.current?.playerEngine.play(show: show, tracks: tracks)
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
