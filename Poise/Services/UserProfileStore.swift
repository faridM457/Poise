import Combine
import Foundation

// The user's own details. Replaces the hardcoded `UserProfile` literal that
// named everyone "Farid" -- the name is now something the user sets and the
// app remembers, and the subtitle is derived from what they have actually
// done rather than being a fixed piece of flattery.
@MainActor
final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()

    private static let nameKey = "poise.userName"
    private static let languageKey = "poise.practiceLanguage"
    private static let soundKey = "poise.soundEffects"

    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) }
    }

    @Published var practiceLanguage: String {
        didSet { UserDefaults.standard.set(practiceLanguage, forKey: Self.languageKey) }
    }

    @Published var soundEffects: Bool {
        didSet { UserDefaults.standard.set(soundEffects, forKey: Self.soundKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        name = defaults.string(forKey: Self.nameKey) ?? ""
        practiceLanguage = defaults.string(forKey: Self.languageKey) ?? "English"
        soundEffects = defaults.object(forKey: Self.soundKey) as? Bool ?? true
    }

    // What the greeting uses. Falls back to a neutral address rather than a
    // placeholder name, so an unset profile never greets the user as someone
    // else.
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "there" : name
    }

    var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}
