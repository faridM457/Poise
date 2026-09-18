import Foundation

// Thin helper around NSUbiquitousKeyValueStore for the handful of keys that
// should survive a reinstall or follow the user to a new device (see
// AccountStore: Sign in with Apple gives a stable identity across devices,
// this is what actually uses that for something besides RevenueCat).
//
// Not every key belongs here -- only real user data (profile, sessions,
// energy). The debug-only toggles in LearnProgressStore (clock offset,
// skip-roleplay) stay on plain UserDefaults: they're testing scaffolding
// meant to be stripped before shipping, not something worth syncing.
enum CloudStore {
    static let store = NSUbiquitousKeyValueStore.default

    // Call once per key, at store init, before reading it. No-ops once KVS
    // has a value for that key, so it's safe to call on every launch, not
    // just the first one after upgrading -- it only ever does real work the
    // one time an existing install picks up this version and would
    // otherwise look like it reset that person's data.
    static func migrateIfNeeded(_ key: String, from defaults: UserDefaults = .standard) {
        guard store.object(forKey: key) == nil, let local = defaults.object(forKey: key) else { return }
        store.set(local, forKey: key)
    }

    // `onChange` fires with the keys that changed on ANOTHER device (or
    // iCloud's own periodic sync) -- callers re-read just those keys and
    // update their own @Published state. Declared @MainActor so callers can
    // touch their (MainActor) store's properties directly instead of each
    // one having to hop actors itself.
    static func observeChanges(_ onChange: @escaping @MainActor ([String]) -> Void) -> NSObjectProtocol {
        store.synchronize()
        return NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            Task { @MainActor in onChange(keys) }
        }
    }
}
