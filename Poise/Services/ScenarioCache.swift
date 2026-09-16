import Foundation

// A generated scenario, kept so that reopening a lesson shows the same
// situation rather than inventing a new one.
//
// Without this, `LiveLessonViewModel.start()` called /api/scenario on every
// open, and the engine's prompt asks for "a unique instance" each time -- so
// backing out of a lesson and opening it again replaced the situation you had
// just read, and burned two generations doing it. A scenario is a thing you
// are asked to practise, not a slot machine.
//
// The opening line is cached alongside it because it is generated *from* the
// scenario and names its specifics; keeping one without the other would let
// the NPC open by referring to an incident the briefing no longer mentions.
struct CachedScenario: Codable {
    let scenario: EngineScenario
    let character: EngineCharacter
    let openingLine: String
    let openingCharacterName: String
    let generatedAt: Date
}

// Cached per lesson and cleared when that lesson is completed, so the next
// visit gets a genuinely new situation. See LearnProgressStore.recordCompletion.
@MainActor
enum ScenarioCache {
    private static let key = "poise.scenarioCache"

    private static func load() -> [String: CachedScenario] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CachedScenario].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ cache: [String: CachedScenario]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func scenario(for lessonID: String) -> CachedScenario? {
        load()[lessonID]
    }

    static func store(_ cached: CachedScenario, for lessonID: String) {
        var cache = load()
        cache[lessonID] = cached
        save(cache)
    }

    // Called on completion. The next open regenerates, which is the whole
    // point: finishing a lesson is what earns you a new situation.
    static func invalidate(lessonID: String) {
        var cache = load()
        guard cache.removeValue(forKey: lessonID) != nil else { return }
        save(cache)
    }

    static func invalidateAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
