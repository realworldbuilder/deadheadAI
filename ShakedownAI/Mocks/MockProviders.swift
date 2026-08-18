import Foundation

// Mock providers power SwiftUI previews, unit tests, and any state where the
// network is unavailable. Fixture data is small but real (canon shows).

enum MockData {
    static let cornell = Show(
        identifier: "gd1977-05-08.sbd.hicks.4982.sbeok.shnf",
        title: "Grateful Dead Live at Barton Hall, Cornell University on 1977-05-08",
        date: IADates.parse("1977-05-08"),
        dateString: "1977-05-08",
        venue: "Barton Hall, Cornell University",
        location: "Ithaca, NY",
        year: 1977,
        avgRating: 4.9, numReviews: 240, downloads: 1_200_000,
        source: "Soundboard"
    )

    static let veneta = Show(
        identifier: "gd1972-08-27.sbd.miller.97635.flac16",
        title: "Grateful Dead Live at Old Renaissance Faire Grounds on 1972-08-27",
        date: IADates.parse("1972-08-27"),
        dateString: "1972-08-27",
        venue: "Old Renaissance Faire Grounds",
        location: "Veneta, OR",
        year: 1972,
        avgRating: 4.8, numReviews: 180, downloads: 800_000,
        source: "SBD Charlie Miller"
    )

    static let fillmore70 = Show(
        identifier: "gd1970-02-13.sbd.gems.16793.sbeok.shnf",
        title: "Grateful Dead Live at Fillmore East on 1970-02-13",
        date: IADates.parse("1970-02-13"),
        dateString: "1970-02-13",
        venue: "Fillmore East",
        location: "New York, NY",
        year: 1970,
        avgRating: 4.7, numReviews: 120, downloads: 500_000,
        source: "Soundboard"
    )

    static let shows: [Show] = [cornell, veneta, fillmore70]

    static let cornellTracks: [Track] = [
        Track(fileName: "gd77-05-08d1t01.mp3", title: "New Minglewood Blues", trackNumber: 1, durationSeconds: 274),
        Track(fileName: "gd77-05-08d1t02.mp3", title: "Loser", trackNumber: 2, durationSeconds: 431),
        Track(fileName: "gd77-05-08d1t03.mp3", title: "El Paso", trackNumber: 3, durationSeconds: 264),
        Track(fileName: "gd77-05-08d2t04.mp3", title: "Scarlet Begonias", trackNumber: 4, durationSeconds: 587),
        Track(fileName: "gd77-05-08d2t05.mp3", title: "Fire On The Mountain", trackNumber: 5, durationSeconds: 917),
        Track(fileName: "gd77-05-08d3t06.mp3", title: "Morning Dew", trackNumber: 6, durationSeconds: 841),
    ]

    static let cornellDetail = RecordingDetail(
        identifier: cornell.identifier,
        title: cornell.title,
        dateString: "1977-05-08",
        venue: cornell.venue,
        location: cornell.location,
        source: "Soundboard, Betty Cantor master",
        lineage: "SBD > Master Reel > Cassette > DAT > CD > EAC > SHN",
        notes: "The legendary Barton Hall show. Widely traded from Betty Boards.",
        setlistText: "New Minglewood Blues, Loser, El Paso, Scarlet Begonias > Fire On The Mountain, Morning Dew",
        tracks: cornellTracks,
        reviews: [
            Review(title: "The one everyone starts with", body: "The Scarlet>Fire is the reference version. Morning Dew closes at emotional peak.", stars: 5, reviewer: "deadfan77", dateString: "2005-03-11"),
            Review(title: "Believe the hype", body: "Crisp Betty board, band absolutely locked in.", stars: 5, reviewer: "archivist", dateString: "2010-08-02"),
        ]
    )
}

// MARK: - Recording / metadata mocks

final class MockRecordingProvider: LiveRecordingProvider, MetadataProvider {
    var showsResult: [Show] = MockData.shows
    var detailResult: RecordingDetail = MockData.cornellDetail

    func shows(matching filters: SearchFilters) async throws -> [Show] { showsResult }
    func recordings(forDate day: String) async throws -> [Show] {
        showsResult.filter { $0.dateString == day }.ifEmpty(showsResult)
    }
    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async throws -> [Show] { showsResult }
    func onThisDay(monthDay: String) async throws -> [Show] { showsResult }
    func detail(for identifier: String) async throws -> RecordingDetail { detailResult }
}

final class MockStreamingProvider: StreamingProvider {
    func streamURL(identifier: String, track: Track) -> URL? {
        URL(string: "https://example.com/\(identifier)/\(track.fileName)")
    }
}

// MARK: - AI stub (replaced by LocalKnowledgeAI at runtime; used in previews/tests)

final class MockAIProvider: AIProvider {
    let name = "Mock AI"

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Man, that's a great question. ")
            continuation.yield("Cornell '77 is where most folks begin — warm, patient, and perfectly recorded.")
            continuation.finish()
        }
    }

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        let pick = candidates.first ?? MockData.cornell
        return Recommendation(
            chosenIdentifier: pick.identifier,
            narrative: "You've been circling Spring '77 — tonight, go to the source. Barton Hall rewards full attention: the Scarlet > Fire is the reference version, and Morning Dew closes the night at an emotional peak.",
            hook: "The one every Deadhead eventually comes home to.",
            listenFor: ["The Scarlet > Fire transition", "Jerry's Morning Dew solo", "Phil's low-end punctuation in Loser"]
        )
    }

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        ShowGuide(
            overallMood: "Warm, confident, unhurried",
            historicalContext: "Spring 1977 caught the band at peak precision after the 1975 hiatus.",
            musicalHighlights: ["Scarlet Begonias > Fire On The Mountain", "Morning Dew"],
            bestTransitions: ["Scarlet > Fire"],
            improvisationRating: 4,
            accessibility: "An ideal first show — clean playing and a famous soundboard.",
            recordingNotes: "Betty Cantor soundboard; rich and balanced.",
            listenFor: ["The pocket between Jerry and Phil in Fire"],
            fanConsensus: "Widely cited as the gateway show.",
            recommendedTracks: ["Scarlet Begonias", "Fire On The Mountain", "Morning Dew"]
        )
    }

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        SearchFilters(freeText: text)
    }

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        SmartCollectionCurator.curate(brief: brief, candidates: candidates)
    }
}

// MARK: - Auth mock

final class MockAuthProvider: AuthProvider {
    private(set) var currentAccount: UserAccount?

    func signInLocally(displayName: String) async throws -> UserAccount {
        let account = UserAccount(displayName: displayName, appleUserID: nil)
        currentAccount = account
        return account
    }

    func signInWithApple(userID: String, displayName: String) async throws -> UserAccount {
        let account = UserAccount(displayName: displayName, appleUserID: userID)
        currentAccount = account
        return account
    }

    func signOut() async {
        currentAccount = nil
        KeychainStore.lockAI()
    }
}

// MARK: - Helpers

extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] { isEmpty ? fallback : self }
}
