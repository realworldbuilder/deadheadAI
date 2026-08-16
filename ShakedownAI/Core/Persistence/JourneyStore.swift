import Foundation
import SwiftData

/// Long Strange Trip journey progression.
@Observable
final class JourneyStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    func state(for journeyID: String) -> JourneyState? {
        let descriptor = FetchDescriptor<JourneyState>(
            predicate: #Predicate { $0.journeyID == journeyID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    func start(journeyID: String) -> JourneyState {
        if let existing = state(for: journeyID) { return existing }
        let state = JourneyState(journeyID: journeyID)
        context.insert(state)
        try? context.save()
        return state
    }

    func completeDay(journeyID: String, dayIndex: Int, totalDays: Int) {
        let state = start(journeyID: journeyID)
        var completed = Set(state.completedDayIndices)
        completed.insert(dayIndex)
        state.completedDayIndices = completed.sorted()
        state.currentDayIndex = min((completed.max() ?? -1) + 1, totalDays - 1)
        if completed.count >= totalDays {
            state.completedAt = .now
        }
        try? context.save()
    }

    func abandon(journeyID: String) {
        if let state = state(for: journeyID) {
            context.delete(state)
            try? context.save()
        }
    }

    func progress(for journey: Journey) -> (completed: Int, total: Int, isStarted: Bool, isFinished: Bool) {
        guard let state = state(for: journey.id) else {
            return (0, journey.days.count, false, false)
        }
        let done = state.completedDayIndices.count
        return (done, journey.days.count, true, state.completedAt != nil)
    }
}
