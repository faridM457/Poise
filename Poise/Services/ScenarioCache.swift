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

    // A scenario cached before EngineCharacter.gender existed decodes fine
    // (it's a plain Optional -- a missing JSON key just becomes nil), but
    // that nil then sticks around forever: this cache only clears on
    // completion, and a lesson someone merely opened once, long before
    // this field shipped, would otherwise keep showing the wrong character
    // model indefinitely (falling back to the name-hash alternation --
    // which is how "Priya" ended up on the male model once, in exactly
    // this situation). Treat a missing gender as staleness, not a real
    // "no gender" case: every lesson has one now, so nil can only mean
    // "cached before this field existed" -- invalidate and let the next
    // open regenerate for real, which fixes it permanently for that lesson.
    static func scenario(for lessonID: String) -> CachedScenario? {
        guard let cached = load()[lessonID] else { return nil }
        guard cached.character.gender != nil else {
            invalidate(lessonID: lessonID)
            return nil
        }
        return cached
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
