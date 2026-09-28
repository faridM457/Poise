import Combine
import Foundation
import OneSignalFramework
import UIKit
import UserNotifications

enum OneSignalMessagingContract {
    enum Tag {
        static let subscriptionTier = "subscription_tier"
        static let streakCount = "streak_count"
        static let streakExpiresAt = "streak_expires_at"
        static let lastPracticeAt = "last_practice_at"
        static let weeklyPracticesCompleted = "weekly_practices_completed"
        static let dailyRemindersEnabled = "daily_reminders_enabled"
        static let streakAlertsEnabled = "streak_alerts_enabled"
        static let weeklySummaryEnabled = "weekly_summary_enabled"
        static let customScenarioRemindersEnabled = "custom_scenario_reminders_enabled"
        static let unfinishedCustomScenarioID = "unfinished_custom_scenario_id"
        static let unfinishedCustomScenarioStartedAt = "unfinished_custom_scenario_started_at"
        static let engagementNotificationDailyLimit = "engagement_notification_daily_limit"
    }

    enum Event {
        static let lessonCompleted = "lesson_completed"
        static let customScenarioStarted = "custom_scenario_started"
        static let customScenarioCompleted = "custom_scenario_completed"
        static let subscriptionChanged = "subscription_changed"
    }

    enum Property {
        static let scenarioID = "scenario_id"
        static let subscriptionTier = "subscription_tier"
    }
}

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case provisional
    case authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .ephemeral:
            self = .authorized
        case .provisional:
            self = .provisional
        case .denied:
            self = .denied
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .notDetermined
        }
    }
}

struct NotificationPreferences: Codable, Equatable {
    var practiceReminders = false
    var streakExpirationAlerts = false
    var weeklyProgressSummary = false
    var customScenarioReminders = false
}

enum NotificationDestination: Equatable {
    case learn
    case progress
    case customScenario(String?)
    case paywall
}

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published private(set) var pendingDestination: NotificationDestination?

    private init() {}

    func route(_ url: URL) {
        guard url.scheme == "poise" else { return }
        switch url.host {
        case "learn":
            pendingDestination = .learn
        case "progress":
            pendingDestination = .progress
        case "custom-scenario":
            let scenarioID = url.pathComponents.dropFirst().first
            pendingDestination = .customScenario(scenarioID)
        case "paywall":
            pendingDestination = .paywall
        default:
            break
        }
    }

    func consume() -> NotificationDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}

final class OneSignalNotificationClickListener: NSObject, OSNotificationClickListener {
    func onClick(event: OSNotificationClickEvent) {
        guard let urlString = event.result.url, let url = URL(string: urlString) else { return }
        Task { @MainActor in NotificationRouter.shared.route(url) }
    }
}

@MainActor
final class OneSignalNotificationService: ObservableObject {
    static let shared = OneSignalNotificationService()

    @Published private(set) var permissionState: NotificationPermissionState = .notDetermined
    @Published private(set) var preferences: NotificationPreferences

    private static let appID = "5ab9aa1f-2375-4263-b198-4b183aaa40f4"
    private static let preferencesKey = "poise.notificationPreferences"
    private static let subscriptionTierKey = "poise.lastOneSignalSubscriptionTier"
    private static let sentTagsKey = "poise.lastOneSignalTags"
    private static let removedTagMarker = "__poise_removed__"
    private static let activeScenarioIDKey = "poise.activeNotificationScenarioID"
    private static let activeScenarioStartedAtKey = "poise.activeNotificationScenarioStartedAt"

    private let clickListener = OneSignalNotificationClickListener()
    private var isInitialized = false
    private var lastSentTags: [String: String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = NotificationPreferences()
        }
        lastSentTags = UserDefaults.standard.dictionary(forKey: Self.sentTagsKey) as? [String: String] ?? [:]
    }

    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        #endif
        OneSignal.initialize(Self.appID, withLaunchOptions: nil)
        OneSignal.Notifications.addClickListener(clickListener)
        synchronizeIdentity(AccountStore.shared.appleUserID)
        Task { await refreshPermissionState() }
    }

    func synchronizeIdentity(_ stableUserID: String?) {
        // Tags belong to the current OneSignal user context. Force one fresh
        // synchronization after login/logout instead of reusing the anonymous
        // user's local deduplication cache.
        lastSentTags = [:]
        persistSentTags()
        if let stableUserID, !stableUserID.isEmpty {
            OneSignal.login(stableUserID)
        } else {
            OneSignal.logout()
        }
    }

    func refreshPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionState = NotificationPermissionState(settings.authorizationStatus)
    }

    func setPracticeReminders(_ enabled: Bool) async {
        await updatePreference(\.practiceReminders, enabled: enabled)
    }

    func setStreakExpirationAlerts(_ enabled: Bool) async {
        await updatePreference(\.streakExpirationAlerts, enabled: enabled)
    }

    func setWeeklyProgressSummary(_ enabled: Bool) async {
        await updatePreference(\.weeklyProgressSummary, enabled: enabled)
    }

    func setCustomScenarioReminders(_ enabled: Bool) async {
        await updatePreference(\.customScenarioReminders, enabled: enabled)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func synchronizeUserData(isPro: Bool, progress: LearnProgressStore) {
        let defaults = UserDefaults.standard
        let tags: [String: String?] = [
            OneSignalMessagingContract.Tag.subscriptionTier: isPro ? "pro" : "free",
            OneSignalMessagingContract.Tag.streakCount: String(progress.currentStreak),
            OneSignalMessagingContract.Tag.streakExpiresAt: timestamp(progress.streakExpiresAt),
            OneSignalMessagingContract.Tag.lastPracticeAt: timestamp(progress.sessions.map(\.finishedAt).max()),
            OneSignalMessagingContract.Tag.weeklyPracticesCompleted: String(progress.conversationsThisWeek),
            OneSignalMessagingContract.Tag.dailyRemindersEnabled: String(preferences.practiceReminders),
            OneSignalMessagingContract.Tag.streakAlertsEnabled: String(preferences.streakExpirationAlerts),
            OneSignalMessagingContract.Tag.weeklySummaryEnabled: String(preferences.weeklyProgressSummary),
            OneSignalMessagingContract.Tag.customScenarioRemindersEnabled: String(preferences.customScenarioReminders),
            OneSignalMessagingContract.Tag.unfinishedCustomScenarioID: defaults.string(forKey: Self.activeScenarioIDKey),
            OneSignalMessagingContract.Tag.unfinishedCustomScenarioStartedAt: timestamp(defaults.object(forKey: Self.activeScenarioStartedAtKey) as? Date),
            OneSignalMessagingContract.Tag.engagementNotificationDailyLimit: "2"
        ]
        synchronizeTags(tags)
    }

    func recordLessonCompleted() {
        guard isInitialized else { return }
        OneSignal.User.trackEvent(name: OneSignalMessagingContract.Event.lessonCompleted, properties: [:])
    }

    func recordCustomScenarioStarted(_ scenario: CustomScenario) {
        let startedAt = CustomScenarioStore.shared.markStarted(scenario)
        let defaults = UserDefaults.standard
        defaults.set(scenario.id, forKey: Self.activeScenarioIDKey)
        defaults.set(startedAt, forKey: Self.activeScenarioStartedAtKey)
        synchronizeTags([
            OneSignalMessagingContract.Tag.unfinishedCustomScenarioID: scenario.id,
            OneSignalMessagingContract.Tag.unfinishedCustomScenarioStartedAt: timestamp(startedAt)
        ])
        guard isInitialized else { return }
        OneSignal.User.trackEvent(
            name: OneSignalMessagingContract.Event.customScenarioStarted,
            properties: [OneSignalMessagingContract.Property.scenarioID: scenario.id]
        )
    }

    func recordCustomScenarioCompleted(_ scenario: CustomScenario) {
        CustomScenarioStore.shared.remove(scenario.id)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.activeScenarioIDKey) == scenario.id {
            defaults.removeObject(forKey: Self.activeScenarioIDKey)
            defaults.removeObject(forKey: Self.activeScenarioStartedAtKey)
            synchronizeTags([
                OneSignalMessagingContract.Tag.unfinishedCustomScenarioID: nil,
                OneSignalMessagingContract.Tag.unfinishedCustomScenarioStartedAt: nil
            ])
        }
        synchronizeUserData(isPro: SubscriptionStore.shared.isPro, progress: LearnProgressStore.shared)
        guard isInitialized else { return }
        OneSignal.User.trackEvent(
            name: OneSignalMessagingContract.Event.customScenarioCompleted,
            properties: [OneSignalMessagingContract.Property.scenarioID: scenario.id]
        )
    }

    func recordSubscriptionChanged(isPro: Bool) {
        let tier = isPro ? "pro" : "free"
        let previousTier = UserDefaults.standard.string(forKey: Self.subscriptionTierKey)
        UserDefaults.standard.set(tier, forKey: Self.subscriptionTierKey)
        guard let previousTier, previousTier != tier else { return }
        guard isInitialized else { return }
        OneSignal.User.trackEvent(
            name: OneSignalMessagingContract.Event.subscriptionChanged,
            properties: [OneSignalMessagingContract.Property.subscriptionTier: tier]
        )
    }

    private func updatePreference(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>,
        enabled: Bool
    ) async {
        if enabled {
            await refreshPermissionState()
            if permissionState == .notDetermined {
                _ = await withCheckedContinuation { continuation in
                    OneSignal.Notifications.requestPermission({ accepted in
                        continuation.resume(returning: accepted)
                    }, fallbackToSettings: false)
                }
                await refreshPermissionState()
            }
            guard permissionState == .authorized || permissionState == .provisional else { return }
        }
        preferences[keyPath: keyPath] = enabled
        persistPreferences()
        synchronizeUserData(isPro: SubscriptionStore.shared.isPro, progress: LearnProgressStore.shared)
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.preferencesKey)
    }

    private func synchronizeTags(_ desiredTags: [String: String?]) {
        guard isInitialized else { return }
        var additions: [String: String] = [:]
        var removals: [String] = []

        for (key, value) in desiredTags {
            let cachedValue = lastSentTags[key]
            if let value {
                guard cachedValue != value else { continue }
                additions[key] = value
                lastSentTags[key] = value
            } else {
                guard cachedValue != Self.removedTagMarker else { continue }
                removals.append(key)
                lastSentTags[key] = Self.removedTagMarker
            }
        }

        if !additions.isEmpty {
            OneSignal.User.addTags(additions)
        }
        for key in removals {
            OneSignal.User.removeTag(key)
        }
        if !additions.isEmpty || !removals.isEmpty {
            persistSentTags()
        }
    }

    private func timestamp(_ date: Date?) -> String? {
        date.map { String(Int($0.timeIntervalSince1970)) }
    }

    private func persistSentTags() {
        UserDefaults.standard.set(lastSentTags, forKey: Self.sentTagsKey)
    }
}

@MainActor
final class CustomScenarioStore {
    static let shared = CustomScenarioStore()

    private static let key = "poise.unfinishedCustomScenarios"
    private static let startedAtKey = "poise.unfinishedCustomScenarioStartedAt"

    private init() {}

    func scenario(id: String) -> CustomScenario? {
        load()[id]
    }

    func markStarted(_ scenario: CustomScenario) -> Date {
        var scenarios = load()
        scenarios[scenario.id] = scenario
        save(scenarios)
        var startedDates = loadStartedDates()
        let startedAt = startedDates[scenario.id] ?? Date()
        startedDates[scenario.id] = startedAt
        saveStartedDates(startedDates)
        return startedAt
    }

    func remove(_ id: String) {
        var scenarios = load()
        scenarios.removeValue(forKey: id)
        save(scenarios)
        var startedDates = loadStartedDates()
        startedDates.removeValue(forKey: id)
        saveStartedDates(startedDates)
    }

    private func load() -> [String: CustomScenario] {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let scenarios = try? JSONDecoder().decode([String: CustomScenario].self, from: data)
        else { return [:] }
        return scenarios
    }

    private func save(_ scenarios: [String: CustomScenario]) {
        guard let data = try? JSONEncoder().encode(scenarios) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private func loadStartedDates() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: Self.startedAtKey),
              let dates = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return dates
    }

    private func saveStartedDates(_ dates: [String: Date]) {
        guard let data = try? JSONEncoder().encode(dates) else { return }
        UserDefaults.standard.set(data, forKey: Self.startedAtKey)
    }
}
