import Testing
@testable import ShakedownAI

struct SmokeTests {
    @Test func modelContainerBuildsInMemory() async throws {
        let container = await ModelContainerFactory.make(inMemory: true)
        _ = container
    }
}
