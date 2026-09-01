import Foundation
import SkywaveKit
import UserNotifications

/// Two notifications, and deliberately no others.
///
/// Nothing is posted for track changes: an Airtime station turns over every few
/// minutes, which would be twenty banners an hour and would get the whole lot
/// muted along with the useful ones.
@MainActor
final class Notifications {
    private var isAuthorized = false
    /// The last show announced per station, so a repeated poll answer is silent.
    private var announced: [String: String] = [:]
    /// Stations already reported unreachable, cleared when they come back.
    private var reportedTrouble: Set<String> = []

    func requestAuthorization() {
        Task {
            let center = UNUserNotificationCenter.current()
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// The show on the station being listened to has changed.
    func showChanged(station: Station, to show: String) {
        guard announced[station.id] != show else { return }
        let isFirst = announced[station.id] == nil
        announced[station.id] = show
        // The first answer after tuning in is not a change; the panel already
        // shows it, and a banner for it would fire on every station switch.
        guard !isFirst else { return }
        post(title: station.name, body: show, id: "show-\(station.id)")
    }

    /// Reconnects keep failing. Silence on its own is ambiguous — it reads the
    /// same as a deliberate pause.
    func unreachable(station: Station) {
        guard !reportedTrouble.contains(station.id) else { return }
        reportedTrouble.insert(station.id)
        post(
            title: station.name,
            body: "Not responding. Still trying.",
            id: "trouble-\(station.id)"
        )
    }

    func recovered(station: Station) {
        reportedTrouble.remove(station.id)
    }

    /// Forgets what was announced, so tuning back in later is not silent.
    func reset(station: Station) {
        announced[station.id] = nil
    }

    private func post(title: String, body: String, id: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
