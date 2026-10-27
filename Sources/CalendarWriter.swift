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
    static func requestAuthorization() async -> Bool {
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
        let date = item.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).weekday(.short).day().month(.abbreviated).hour().minute())
        content.body = "\(item.title) • \(date)"
        content.sound = .default
        content.threadIdentifier = "librussync-events"
        let request = UNNotificationRequest(
            identifier: "librussync-\(item.uid)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
