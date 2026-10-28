import Foundation
import Combine
import EventKit
import UserNotifications

struct AppleCalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
}

@MainActor
final class CalendarWriter: ObservableObject {
    static let shared = CalendarWriter()

    @Published private(set) var calendars: [AppleCalendarChoice] = []
    @Published private(set) var selectedCalendarIdentifier: String?

    private let store = EKEventStore()
    private let calendarName = "LibrusSync"
    private let selectedKey = "selectedAppleCalendarIdentifier"

    private init() { selectedCalendarIdentifier = UserDefaults.standard.string(forKey: selectedKey) }

    func prepareAccessAndLoadCalendars() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw SyncError.calendarPermissionDenied }

        var writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if writable.isEmpty { writable = [try createDefaultCalendar()] }

        calendars = writable.map {
            AppleCalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let saved = UserDefaults.standard.string(forKey: selectedKey)
        if let saved, calendars.contains(where: { $0.id == saved }) {
            selectedCalendarIdentifier = saved
        } else if let preferred = calendars.first(where: { $0.title == calendarName }) {
            selectedCalendarIdentifier = preferred.id
        } else if let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier,
                  calendars.contains(where: { $0.id == defaultID }) {
            selectedCalendarIdentifier = defaultID
        } else {
            selectedCalendarIdentifier = calendars.first?.id
        }
        if let selectedCalendarIdentifier {
            UserDefaults.standard.set(selectedCalendarIdentifier, forKey: selectedKey)
        }
    }

    func selectCalendar(identifier: String) {
        guard calendars.contains(where: { $0.id == identifier }) else { return }
        selectedCalendarIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: selectedKey)
    }

    func upsert(_ item: AgendaEvent) throws {
        let calendar = try targetCalendar()
        let marker = "LibrusSyncUID:\(item.uid)"
        let predicate = store.predicateForEvents(
            withStart: item.startDate.addingTimeInterval(-86_400 * 370),
            end: item.endDate.addingTimeInterval(86_400 * 370),
            calendars: nil
        )
        let existing = store.events(matching: predicate).first { $0.notes?.contains(marker) == true }
        let event = existing ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = item.title
        event.startDate = item.startDate
        event.endDate = item.endDate
        event.isAllDay = item.isAllDay
        let details = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = details.isEmpty ? marker : "\(details)\n\n\(marker)"
        try store.save(event, span: .thisEvent, commit: true)
    }

    /// Removes only events previously written by LibrusSync that have vanished
    /// from a non-empty, successfully fetched Librus snapshot.
    func removeSyncedEvents(notIn liveUIDs: Set<String>) throws -> Int {
        guard !liveUIDs.isEmpty else { return 0 }
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return 0 }

        let start = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? .distantPast
        let end = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? .distantFuture
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let markerPrefix = "LibrusSyncUID:"
        let staleEvents = store.events(matching: predicate).filter { event in
            guard let notes = event.notes,
                  let range = notes.range(of: markerPrefix) else { return false }
            let markerValue = notes[range.upperBound...]
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? ""
            return !markerValue.isEmpty && !liveUIDs.contains(markerValue)
        }

        for event in staleEvents {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        if !staleEvents.isEmpty { try store.commit() }
        return staleEvents.count
    }

    private func targetCalendar() throws -> EKCalendar {
        if let id = selectedCalendarIdentifier,
           let choice = store.calendar(withIdentifier: id), choice.allowsContentModifications { return choice }
        if let id = UserDefaults.standard.string(forKey: selectedKey),
           let choice = store.calendar(withIdentifier: id), choice.allowsContentModifications { return choice }
        let created = try createDefaultCalendar()
        selectedCalendarIdentifier = created.calendarIdentifier
        UserDefaults.standard.set(created.calendarIdentifier, forKey: selectedKey)
        return created
    }

    private func createDefaultCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarName && $0.allowsContentModifications }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
                ?? store.sources.first else {
            throw SyncError.noCalendarSource
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

enum LocalNotificationService {
    static func configure() {
        UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
    }

    static func requestAuthorization() async -> Bool {
        configure()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { return true }
        guard settings.authorizationStatus == .notDetermined else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func notify(for item: AgendaEvent, updated: Bool) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = updated ? "Zmieniono wpis w terminarzu" : "Nowy wpis w terminarzu"
        let locale = Locale(identifier: "pl_PL")
        let date = item.startDate.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide).year())
        let timing: String
        if item.isAllDay {
            timing = "cały dzień"
        } else if Calendar.current.isDate(item.startDate, inSameDayAs: item.endDate) {
            let start = item.startDate.formatted(.dateTime.locale(locale).hour().minute())
            let end = item.endDate.formatted(.dateTime.locale(locale).hour().minute())
            timing = "\(start)–\(end)"
        } else {
            let start = item.startDate.formatted(.dateTime.locale(locale).day().month(.wide).year().hour().minute())
            let end = item.endDate.formatted(.dateTime.locale(locale).day().month(.wide).year().hour().minute())
            timing = "\(start) – \(end)"
        }
        content.body = "\(item.title) • \(date), \(timing)"
        content.sound = .default
        content.threadIdentifier = "librussync-events"
        let request = UNNotificationRequest(
            identifier: "librussync-\(item.uid)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("LibrusSync: nie udało się zaplanować powiadomienia: \(error.localizedDescription)")
        }
    }

    /// Refreshes local reminders according to the user's preferences.
    /// iOS limits pending local notifications, so only the 60 soonest alerts are kept.
    static func scheduleReminders(for events: [AgendaEvent]) async {
        guard await requestAuthorization() else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = "librussync-reminder-"
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        let defaults = UserDefaults.standard
        let options: [(key: String, daysBefore: Int, label: String, defaultValue: Bool)] = [
            ("reminderWeekBefore", 7, "Za 7 dni", false),
            ("reminderTwoDays", 2, "Za 2 dni", true),
            ("reminderSameDay", 0, "Dzisiaj", false)
        ]
        let enabled = options.filter { option in
            (defaults.object(forKey: option.key) as? Bool) ?? option.defaultValue
        }
        guard !enabled.isEmpty else { return }

        let now = Date()
        let alerts = events
            .filter { $0.isUpcoming }
            .flatMap { item in
                enabled.compactMap { option -> (item: AgendaEvent, option: (key: String, daysBefore: Int, label: String, defaultValue: Bool), fireDate: Date)? in
                    guard let fireDate = reminderDate(for: item, daysBefore: option.daysBefore),
                          fireDate > now else { return nil }
                    return (item, option, fireDate)
                }
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(60)

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = "\(alert.option.label): \(alert.item.title)"
            content.body = notificationDateDescription(for: alert.item)
            content.sound = .default
            content.threadIdentifier = "librussync-reminders"

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: alert.fireDate
            )
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(alert.item.uid)-\(alert.option.daysBefore)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                print("LibrusSync: nie udało się zaplanować przypomnienia: \(error.localizedDescription)")
            }
        }
    }

    private static func reminderDate(for item: AgendaEvent, daysBefore: Int) -> Date? {
        let calendar = Calendar.current
        guard let original = calendar.date(byAdding: .day, value: -daysBefore, to: item.startDate) else { return nil }

        if item.isAllDay {
            // All-day reminders are delivered at 09:00 local time.
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: original)
        }

        if daysBefore == 0 {
            // On the same day, remind at 07:00 only if that is before the event starts.
            guard let reminder = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: original),
                  reminder < item.startDate else { return nil }
            return reminder
        }
        // Preserve the event's local wall-clock time on the selected day.
        let time = calendar.dateComponents([.hour, .minute, .second], from: item.startDate)
        return calendar.date(
            bySettingHour: time.hour ?? 8,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: original
        )
    }

    private static func notificationDateDescription(for item: AgendaEvent) -> String {
        let locale = Locale(identifier: "pl_PL")
        let date = item.startDate.formatted(
            .dateTime.locale(locale).weekday(.wide).day().month(.wide).year()
        )
        if item.isAllDay {
            return "\(date) • cały dzień"
        }
        let start = item.startDate.formatted(.dateTime.locale(locale).hour().minute())
        if Calendar.current.isDate(item.startDate, inSameDayAs: item.endDate) {
            let end = item.endDate.formatted(.dateTime.locale(locale).hour().minute())
            return "\(date) • \(start)–\(end)"
        }
        let endDate = item.endDate.formatted(
            .dateTime.locale(locale).weekday(.wide).day().month(.wide).year().hour().minute()
        )
        return "\(date) • od \(start) do \(endDate)"
    }

    /// Schedules a real local notification so the user can verify iOS permissions
    /// and the installed IPA's notification behavior without waiting for a new event.
    static func sendTestNotification() async -> (success: Bool, message: String) {
        configure()
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            let granted = await requestAuthorization()
            settings = await center.notificationSettings()
            if !granted && settings.authorizationStatus != .provisional {
                return (false, "Nie przyznano zgody na powiadomienia. Włącz je w Ustawieniach iPhone’a → Powiadomienia → LibrusSync.")
            }
        }

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return (false, "Powiadomienia są zablokowane. Otwórz Ustawienia iPhone’a → Powiadomienia → LibrusSync i włącz „Dopuszczaj powiadomienia”.")
        }

        let content = UNMutableNotificationContent()
        content.title = "LibrusSync działa!"
        content.body = "To jest testowe powiadomienie. Powiadomienia są poprawnie skonfigurowane."
        content.sound = .default
        content.threadIdentifier = "librussync-test"
        let request = UNNotificationRequest(
            identifier: "librussync-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )

        do {
            try await center.add(request)
            return (true, "Testowe powiadomienie zaplanowano. Powinno pojawić się za około 2 sekundy. Jeśli aplikacja jest otwarta, wyświetli się jako baner.")
        } catch {
            return (false, "iOS nie przyjął powiadomienia: \(error.localizedDescription)")
        }
    }
}


private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresentationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
