import Foundation
import SwiftData
import Testing
@testable import ShakedownAI

// MARK: - Playlist CRUD & dedup

struct PlaylistStoreTests {
    // The container must outlive the test body — a context whose container
    // deallocates traps on first use.
    private func makeStore() -> (LibraryStore, ModelContext, ModelContainer) {
        let container = ModelContainerFactory.make(inMemory: true)
        return (LibraryStore(container: container), container.mainContext, container)
    }

    @Test func addingTracksSnapshotsEverythingNeededToPlayOffline() throws {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Segue Lab")
        store.add(tracks: Array(MockData.cornellTracks.prefix(2)), from: MockData.cornell, to: playlist)

        let items = store.sortedItems(of: playlist)
        #expect(items.count == 2)
        let first = try #require(items.first)
        #expect(first.showIdentifier == MockData.cornell.identifier)
        #expect(first.fileName == MockData.cornellTracks[0].fileName)
        #expect(first.trackTitle == MockData.cornellTracks[0].title)
        #expect(first.songKey == MockData.cornellTracks[0].songKey)
        #expect(first.durationSeconds == MockData.cornellTracks[0].durationSeconds)
        #expect(items.map(\.sortIndex) == [0, 1])
    }

    @Test func addingTheSameTrackTwiceIsANoOpButSameFileNameFromAnotherShowIsNot() {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Mixtape")
        let track = Track(fileName: "t01.mp3", title: "Bertha", trackNumber: 1, durationSeconds: 300)

        store.add(tracks: [track], from: MockData.cornell, to: playlist)
        store.add(tracks: [track], from: MockData.cornell, to: playlist)   // dupe — skipped
        store.add(tracks: [track], from: MockData.veneta, to: playlist)    // same file, other show — kept

        let items = store.sortedItems(of: playlist)
        #expect(items.count == 2)
        #expect(Set(items.map(\.showIdentifier)) == [MockData.cornell.identifier, MockData.veneta.identifier])
        #expect(items.map(\.sortIndex) == [0, 1])
    }

    @Test func removeRenumbersTheRemainingItems() throws {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Mixtape")
        store.add(tracks: Array(MockData.cornellTracks.prefix(3)), from: MockData.cornell, to: playlist)

        let middle = try #require(store.sortedItems(of: playlist).dropFirst().first)
        store.remove(item: middle)

        let items = store.sortedItems(of: playlist)
        #expect(items.count == 2)
        #expect(items.map(\.sortIndex) == [0, 1])
        #expect(items.map(\.trackTitle) == ["New Minglewood Blues", "El Paso"])
    }

    @Test func moveSwapsNeighborsAndClampsAtTheEdges() throws {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Mixtape")
        store.add(tracks: Array(MockData.cornellTracks.prefix(3)), from: MockData.cornell, to: playlist)

        let first = try #require(store.sortedItems(of: playlist).first)
        store.move(item: first, up: true)      // clamped — already at the top
        #expect(store.sortedItems(of: playlist).first?.trackTitle == "New Minglewood Blues")

        store.move(item: first, up: false)
        #expect(store.sortedItems(of: playlist).map(\.trackTitle) ==
                ["Loser", "New Minglewood Blues", "El Paso"])
    }

    @Test func dedupCollapsesDuplicatePlaylistsByIDAndItemsByTrackKey() throws {
        let (store, context, container) = makeStore()
        _ = container
        let sharedID = UUID()

        let older = Playlist(name: "Mixtape")
        older.id = sharedID
        older.createdAt = Date(timeIntervalSince1970: 100)
        context.insert(older)
        let bertha = PlaylistItem(showIdentifier: "gd1977-05-08", fileName: "t01.mp3",
                                  trackTitle: "Bertha", songKey: "bertha",
                                  showDateString: "1977-05-08", showDisplayName: "Cornell",
                                  durationSeconds: 300, sortIndex: 0)
        bertha.playlist = older
        context.insert(bertha)

        let newer = Playlist(name: "Mixtape")
        newer.id = sharedID
        newer.createdAt = Date(timeIntervalSince1970: 200)
        context.insert(newer)
        let berthaDupe = PlaylistItem(showIdentifier: "gd1977-05-08", fileName: "t01.mp3",
                                      trackTitle: "Bertha", songKey: "bertha",
                                      showDateString: "1977-05-08", showDisplayName: "Cornell",
                                      durationSeconds: 300, sortIndex: 0)
        berthaDupe.playlist = newer
        context.insert(berthaDupe)
        let sugaree = PlaylistItem(showIdentifier: "gd1977-05-08", fileName: "t02.mp3",
                                   trackTitle: "Sugaree", songKey: "sugaree",
                                   showDateString: "1977-05-08", showDisplayName: "Cornell",
                                   durationSeconds: 640, sortIndex: 1)
        sugaree.playlist = newer
        context.insert(sugaree)
        try context.save()

        store.dedupAfterSync()

        let survivors = try context.fetch(FetchDescriptor<Playlist>())
        #expect(survivors.count == 1)
        let survivor = try #require(survivors.first)
        #expect(survivor.createdAt == Date(timeIntervalSince1970: 100))
        let items = store.sortedItems(of: survivor)
        // Two tracks share a show — the composite key must keep them both.
        #expect(items.map(\.fileName) == ["t01.mp3", "t02.mp3"])
        #expect(items.map(\.sortIndex) == [0, 1])
    }

    @Test func playlistDedupLeavesShowCollectionsAlone() throws {
        let (store, context, container) = makeStore()
        _ = container
        // A mixed store: one healthy collection, one duplicated playlist.
        let shelf = ShowCollection(name: "Tour Tapes")
        context.insert(shelf)
        let shelfItem = CollectionItem(showIdentifier: "gd1972-08-27", showDate: nil,
                                       displayName: "Veneta", sortIndex: 0)
        shelfItem.collection = shelf
        context.insert(shelfItem)

        let sharedID = UUID()
        for offset in 0..<2 {
            let playlist = Playlist(name: "Mixtape")
            playlist.id = sharedID
            playlist.createdAt = Date(timeIntervalSince1970: Double(100 + offset))
            context.insert(playlist)
        }
        try context.save()

        store.dedupAfterSync()

        #expect(try context.fetch(FetchDescriptor<Playlist>()).count == 1)
        let shelves = try context.fetch(FetchDescriptor<ShowCollection>())
        #expect(shelves.count == 1)
        #expect((shelves.first?.items ?? []).count == 1)
    }

    @Test func reorderRewritesSortIndexesToTheGivenKeyOrder() {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Mixtape")
        store.add(tracks: Array(MockData.cornellTracks.prefix(3)), from: MockData.cornell, to: playlist)

        let items = store.sortedItems(of: playlist)
        store.reorder(playlist, toTrackKeys: [items[2].trackKey, items[0].trackKey, items[1].trackKey])

        #expect(store.sortedItems(of: playlist).map(\.trackTitle) ==
                ["El Paso", "New Minglewood Blues", "Loser"])
    }

    @Test func playlistItemsBecomeCorrectQueueEntries() {
        let (store, _, container) = makeStore()
        _ = container
        let playlist = store.createPlaylist(name: "Mixtape")
        store.add(tracks: Array(MockData.cornellTracks.prefix(2)), from: MockData.cornell, to: playlist)

        let entries = store.sortedItems(of: playlist).map(\.queueEntry)
        #expect(entries.map(\.show.identifier) == [MockData.cornell.identifier, MockData.cornell.identifier])
        #expect(entries.map(\.track.fileName) == MockData.cornellTracks.prefix(2).map(\.fileName))
        // The exact inputs StreamingProvider needs — enough to play with no network.
        let url = MockStreamingProvider().streamURL(identifier: entries[0].show.identifier,
                                                    track: entries[0].track)
        #expect(url != nil)
    }
}

// MARK: - Segue suggestions ("Flow")

struct SegueSuggesterTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    @Test func suggestionsAreDeterministicAndComeFromTheKnowledgeBase() {
        let a = SegueSuggester.nextPicks(after: ["scarlet begonias"], kb: kb)
        let b = SegueSuggester.nextPicks(after: ["scarlet begonias"], kb: kb)
        #expect(a == b)
        #expect(!a.isEmpty)
        let knownKeys = Set(kb.songs.map(\.key))
        #expect(a.allSatisfy { knownKeys.contains($0.songKey) })
    }

    @Test func scarletTailSuggestsFire() {
        let picks = SegueSuggester.nextPicks(after: ["bertha", "scarlet begonias"], kb: kb)
        #expect(picks.first?.songKey == "fire on the mountain")
        // Scarlet > Fire is canon (Cornell) — the reason should say so.
        #expect(picks.first?.famousDate == "1977-05-08")
    }

    @Test func songsAlreadyOnThePlaylistAreNeverSuggested() {
        let picks = SegueSuggester.nextPicks(after: ["scarlet begonias", "fire on the mountain"], kb: kb)
        #expect(!picks.contains { $0.songKey == "scarlet begonias" || $0.songKey == "fire on the mountain" })
    }

    @Test func shuffledSeguePairsGetReunitedByTheSuggestedOrder() {
        let items = [
            (key: "a", songKey: "scarlet begonias"),
            (key: "b", songKey: "china cat sunflower"),
            (key: "c", songKey: "fire on the mountain"),
            (key: "d", songKey: "i know you rider"),
        ]
        let order = SegueSuggester.suggestedOrder(for: items, kb: kb)
        #expect(order == ["a", "c", "b", "d"])
    }

    @Test func alreadyOptimalOrderReturnsNil() {
        let items = [
            (key: "a", songKey: "scarlet begonias"),
            (key: "b", songKey: "fire on the mountain"),
            (key: "c", songKey: "china cat sunflower"),
            (key: "d", songKey: "i know you rider"),
        ]
        #expect(SegueSuggester.suggestedOrder(for: items, kb: kb) == nil)
    }

    @Test func tinyPlaylistsAreLeftAlone() {
        let items = [(key: "a", songKey: "scarlet begonias"), (key: "b", songKey: "ripple")]
        #expect(SegueSuggester.suggestedOrder(for: items, kb: kb) == nil)
    }
}
