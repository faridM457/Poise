import Combine
import Foundation
import OneSignalFramework
import UIKit
import UserNotifications

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

    private let clickListener = OneSignalNotificationClickListener()
    private var isInitialized = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = NotificationPreferences()
        }
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
        let lastPractice = progress.sessions.last?.finishedAt
        let streakExpiration = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: progress.practisedToday ? progress.now.addingTimeInterval(86_400) : progress.now
        )
        let tags: [String: String] = [
            "subscription_tier": isPro ? "pro" : "free",
            "streak_count": String(progress.currentStreak),
            "streak_expires_at": timestamp(streakExpiration),
            "last_practice_at": timestamp(lastPractice),
            "weekly_xp": String(progress.weeklyXP),
            "daily_reminders_enabled": String(preferences.practiceReminders),
            "streak_alerts_enabled": String(preferences.streakExpirationAlerts),
            "weekly_summary_enabled": String(preferences.weeklyProgressSummary),
            "custom_scenario_reminders_enabled": String(preferences.customScenarioReminders),
            "engagement_notification_daily_limit": "2"
        ]
        OneSignal.User.addTags(tags)
    }

    func recordLessonCompleted() {
        OneSignal.User.trackEvent(name: "lesson_completed", properties: [:])
    }

    // The source branch this was ported from tracked an "unfinished custom
    // scenario" concept (CustomScenarioStore, saved/resumed via a mock
    // CustomScenario model) that belonged to the old mock-based custom
    // scenario flow -- that flow, and its model, are gone, replaced by the
    // real engine-backed one (see CustomScenarioFlowView.swift), which
    // generates a scenario fresh each time rather than saving one to
    // resume later. Kept the engagement events (still useful for OneSignal
    // targeting/segmentation), dropped the resume-persistence half, which
    // has no equivalent in the real flow.
    func recordCustomScenarioStarted(id: String) {
        OneSignal.User.trackEvent(name: "custom_scenario_started", properties: ["scenario_id": id])
    }

    func recordCustomScenarioCompleted(id: String) {
        OneSignal.User.trackEvent(name: "custom_scenario_completed", properties: ["scenario_id": id])
    }

    func recordSubscriptionChanged(isPro: Bool) {
        let tier = isPro ? "pro" : "free"
        let previousTier = UserDefaults.standard.string(forKey: Self.subscriptionTierKey)
        UserDefaults.standard.set(tier, forKey: Self.subscriptionTierKey)
        guard let previousTier, previousTier != tier else { return }
        OneSignal.User.trackEvent(name: "subscription_changed", properties: ["subscription_tier": tier])
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

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return String(Int(date.timeIntervalSince1970))
    }

}
