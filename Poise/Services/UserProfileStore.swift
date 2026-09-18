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
    private static let nameIsGuestPlaceholderKey = "poise.nameIsGuestPlaceholder"

    // iCloud key-value storage, not UserDefaults -- this is real user data
    // (their name, their settings), so it should follow them across a
    // reinstall or a new device the same way their subscription now does
    // (see AccountStore). CloudStore.migrateIfNeeded in init copies over
    // whatever an existing install already had in UserDefaults, once.
    private let store = CloudStore.store
    private var changeObserver: NSObjectProtocol?

    // Set through the ordinary `name = ...` assignment, this always counts as
    // the user's real name -- including if they happen to type "Guest"
    // themselves. Only `assignGuestPlaceholderName()` marks it as a
    // placeholder, and any subsequent edit through this setter clears that
    // mark again, so it can never stick to a name the user actually chose.
    @Published var name: String {
        didSet {
            store.set(name, forKey: Self.nameKey)
            if !isApplyingGuestPlaceholder {
                nameIsGuestPlaceholder = false
            }
        }
    }

    // Persisted alongside `name` so it stays correct across devices --
    // otherwise a real name synced in from signing in on another device
    // could arrive while this one still thought it was showing a placeholder.
    @Published private(set) var nameIsGuestPlaceholder: Bool {
        didSet { store.set(nameIsGuestPlaceholder, forKey: Self.nameIsGuestPlaceholderKey) }
    }

    private var isApplyingGuestPlaceholder = false

    @Published var practiceLanguage: String {
        didSet { store.set(practiceLanguage, forKey: Self.languageKey) }
    }

    @Published var soundEffects: Bool {
        didSet { store.set(soundEffects, forKey: Self.soundKey) }
    }

    private init() {
        CloudStore.migrateIfNeeded(Self.nameKey)
        CloudStore.migrateIfNeeded(Self.languageKey)
        CloudStore.migrateIfNeeded(Self.soundKey)

        name = store.string(forKey: Self.nameKey) ?? ""
        practiceLanguage = store.string(forKey: Self.languageKey) ?? "English"
        soundEffects = store.object(forKey: Self.soundKey) != nil ? store.bool(forKey: Self.soundKey) : true
        nameIsGuestPlaceholder = store.object(forKey: Self.nameIsGuestPlaceholderKey) != nil
            ? store.bool(forKey: Self.nameIsGuestPlaceholderKey)
            : false

        changeObserver = CloudStore.observeChanges { [weak self] changedKeys in
            self?.applyExternalChanges(changedKeys)
        }
    }

    // Called only when the sign-in prompt is declined or fails -- see
    // SignInPromptSheet.assignGuestNameIfNeeded. Goes through `name`'s own
    // setter (so it persists and syncs exactly like a real name), but flags
    // it as a placeholder immediately after, overriding the setter's own
    // "this must be a real edit" assumption for this one call.
    func assignGuestPlaceholderName() {
        isApplyingGuestPlaceholder = true
        name = "Guest"
        nameIsGuestPlaceholder = true
        isApplyingGuestPlaceholder = false
    }

    // Another device changed one of these -- pull the new value in rather
    // than waiting for a relaunch to notice.
    private func applyExternalChanges(_ changedKeys: [String]) {
        if changedKeys.contains(Self.nameKey) {
            isApplyingGuestPlaceholder = true
            name = store.string(forKey: Self.nameKey) ?? ""
            isApplyingGuestPlaceholder = false
        }
        if changedKeys.contains(Self.languageKey) {
            practiceLanguage = store.string(forKey: Self.languageKey) ?? "English"
        }
        if changedKeys.contains(Self.soundKey) {
            soundEffects = store.bool(forKey: Self.soundKey)
        }
        if changedKeys.contains(Self.nameIsGuestPlaceholderKey) {
            nameIsGuestPlaceholder = store.bool(forKey: Self.nameIsGuestPlaceholderKey)
        }
    }

    // What GreetingHeader appends after "Good afternoon" etc. Empty when no
    // real name is set -- either nothing at all, or only the auto-assigned
    // "Guest" placeholder -- rather than falling back to a filler word like
    // "there": "Good afternoon, there" reads like addressing someone
    // literally named There, since "there" only works after a casual
    // "Hey"/"Hi", not a formal time-of-day greeting. Omitting it entirely
    // ("Good afternoon") is the more natural fallback and keeps the original
    // intent: never greet someone with a name that isn't really theirs.
    // "Guest" itself still shows normally if the user typed it in themselves
    // -- nameIsGuestPlaceholder is what distinguishes the two.
    var displayNameSuffix: String {
        (hasName && !nameIsGuestPlaceholder) ? ", \(name)" : ""
    }

    var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}
