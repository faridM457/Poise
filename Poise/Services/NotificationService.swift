import Foundation
import UserNotifications

// Local-only notifications -- no server, no APNs. Both reminders this drives
// (streak, come-back) are decided entirely from on-device state (see
// LearnProgressStore), so there's nothing for a push service to tell this
// app that it doesn't already know. Scheduling is UNUserNotificationCenter's
// own on-device timer, delivered even if the app is never relaunched.
//
// Deliberately a dumb mechanical wrapper: this file only knows how to build
// and (un)schedule the two requests. It never decides *when* a reminder is
// warranted -- that decision belongs where the relevant state already lives
// (LearnProgressStore.recordCompletion, PoiseRootView's scenePhase handler),
// same division of labor as SpeechRecognitionService not deciding when the
// mic button should be shown.
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    private static let streakReminderID = "poise.notification.streakReminder"
    private static let comeBackReminderID = "poise.notification.comeBackReminder"

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    // MARK: - Authorization
    //
    // Unlike SFSpeechRecognizer.authorizationStatus(), which returns
    // synchronously, UNUserNotificationCenter's settings are only available
    // through an async call (getNotificationSettings' completion handler,
    // or the async notificationSettings() this wraps) -- there's no cached
    // synchronous property Apple exposes. Rather than force a fake sync API
    // (which would either block the main thread or return stale/guessed
    // data), both properties below are `async` and awaited at their two call
    // sites (PrivacyCard's @State seeding and re-sync, and the scenePhase
    // background handler), exactly like SpeechRecognitionService.
    // requestAuthorization() already is.
    static var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    static var isUndetermined: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .notDetermined
        }
    }

    // Static, not instance-bound -- same reasoning as
    // SpeechRecognitionService.requestAuthorization(): the permission toggle
    // needs to call this without going through `shared`.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[NotificationService] requestAuthorization failed: \(error)")
            return false
        }
    }

    // MARK: - Streak reminder
    //
    // "Practice today to keep your streak" -- scheduled by PoiseRootView
    // when the app backgrounds with a live streak still unpractised today,
    // cancelled the moment a session is actually recorded (see
    // LearnProgressStore.recordCompletion) since today's reminder is then
    // moot, whether or not it ever fires.

    func scheduleStreakReminder(streakLength: Int, at date: Date) {
        let dayWord = streakLength == 1 ? "day" : "days"
        let content = UNMutableNotificationContent()
        content.title = "Keep your streak going"
        content.body = "You're on a \(streakLength)-\(dayWord) streak -- one quick conversation keeps it alive."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: Self.streakReminderID, content: content, trigger: trigger)

        // Remove-then-add rather than relying on identifier reuse to
        // implicitly replace the pending request -- explicit about intent,
        // and avoids ever stacking two reminders under the same id.
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakReminderID])
        center.add(request) { error in
            if let error {
                print("[NotificationService] scheduleStreakReminder failed: \(error)")
            }
        }
    }

    func cancelStreakReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakReminderID])
    }

    // MARK: - Come-back reminder
    //
    // "Your next lesson is waiting" -- scheduled unconditionally whenever the
    // app backgrounds (unlike the streak reminder, this doesn't require an
    // active streak; someone with no streak at all still has an "up next").
    // Cancelled the moment the app comes back to the foreground, since the
    // whole point was to get them to open the app again.

    func scheduleComeBackReminder(afterDays: Int, upNextTitle: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Ready for another round?"
        if let upNextTitle, !upNextTitle.isEmpty {
            content.body = "\"\(upNextTitle)\" is up next whenever you're ready."
        } else {
            content.body = "Your next conversation is waiting whenever you're ready."
        }
        content.sound = .default

        let seconds = TimeInterval(max(1, afterDays)) * 24 * 60 * 60
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.comeBackReminderID, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [Self.comeBackReminderID])
        center.add(request) { error in
            if let error {
                print("[NotificationService] scheduleComeBackReminder failed: \(error)")
            }
        }
    }

    func cancelComeBackReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.comeBackReminderID])
    }
}
