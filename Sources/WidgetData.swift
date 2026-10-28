import Foundation
import WidgetKit

enum WidgetDataStore {
    static let appGroupIdentifier = "group.pl.novydev.librussync"
    private static let eventsKey = "widgetUpcomingEvents"

    /// Saves the events and returns a human-readable diagnostic for the app UI.
    @discardableResult
    static func save(events: [AgendaEvent]) -> String {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            return "Widżet: brak dostępu do App Group. Sprawdź podpis IPA i uprawnienia App Groups w iPASide."
        }
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return "Widżet: nie można otworzyć współdzielonych ustawień App Group."
        }
        guard let data = try? JSONEncoder().encode(events) else {
            return "Widżet: nie udało się zakodować wydarzeń."
        }

        defaults.set(data, forKey: eventsKey)
        defaults.set(Date(), forKey: "widgetLastUpdated")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()

        guard let savedData = defaults.data(forKey: eventsKey),
              let savedEvents = try? JSONDecoder().decode([AgendaEvent].self, from: savedData) else {
            return "Widżet: zapis nie został potwierdzony. Sprawdź uprawnienia App Groups."
        }
        return "Widżet: zapisano \(savedEvents.count) wydarzeń."
    }

    static func diagnosticStatus() -> String {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            return "Widżet: brak dostępu do App Group. Sprawdź podpis IPA i uprawnienia App Groups w iPASide."
        }
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return "Widżet: nie można otworzyć współdzielonych ustawień App Group."
        }
        guard let data = defaults.data(forKey: eventsKey),
              let events = try? JSONDecoder().decode([AgendaEvent].self, from: data) else {
            return "Widżet: App Group działa, ale nie ma zapisanych danych. Uruchom synchronizację."
        }
        return "Widżet: App Group działa, zapisano \(events.filter(\.isUpcoming).count) nadchodzących wydarzeń."
    }

    static func loadUpcomingEvents() -> [AgendaEvent] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: eventsKey),
              let events = try? JSONDecoder().decode([AgendaEvent].self, from: data) else { return [] }
        return events.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate }
    }
}
