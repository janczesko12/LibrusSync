import Foundation
import EventKit
import UserNotifications

@MainActor
final class CalendarWriter {
    static let shared = CalendarWriter()

    private let store = EKEventStore()
    private let calendarName = "LibrusSync"

    private init() {}

    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw SyncError.calendarPermissionDenied }
    }

    func upsert(_ item: AgendaEvent) throws {
        let calendar = try librusCalendar()
        let marker = "LibrusSyncUID:\(item.uid)"
        let searchStart = item.startDate.addingTimeInterval(-86_400)
        let searchEnd = item.endDate.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: [calendar])
        let existing = store.events(matching: predicate).first {
            $0.notes?.contains(marker) == true
        }

        let event = existing ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = item.title
        event.startDate = item.startDate
        event.endDate = item.endDate
        let cleanNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = cleanNotes.isEmpty ? marker : "\(cleanNotes)\n\n\(marker)"
        try store.save(event, span: .thisEvent, commit: true)
    }

    private func librusCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarName }) {
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
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional {
            return true
        }
        guard settings.authorizationStatus == .notDetermined else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func notify(for item: AgendaEvent, updated: Bool) async {
        guard await requestAuthorization() else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = updated ? "Zmieniono wpis w terminarzu" : "Nowy wpis w terminarzu"
        let date = item.startDate.formatted(
            .dateTime.locale(Locale(identifier: "pl_PL"))
                .weekday(.short).day().month(.abbreviated).hour().minute()
        )
        content.body = "\(item.title) • \(date)"
        content.sound = .default
        content.threadIdentifier = "librussync-events"

        let request = UNNotificationRequest(
            identifier: "librussync-\(item.uid)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}