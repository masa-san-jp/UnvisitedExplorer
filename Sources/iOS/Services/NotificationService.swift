import Foundation
import UserNotifications

@MainActor
enum NotificationService {
    static func requestAndScheduleDailyReminder(hour: Int = 10) async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["daily-unvisited-reminder"])
        let content = UNMutableNotificationContent()
        content.title = "今日は未訪問エリアへ"
        content.body = "地図を開いて、近くの未訪問エリアを1つ選びましょう。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-unvisited-reminder",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daily-unvisited-reminder"])
    }
}
