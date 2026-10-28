import Foundation
import WidgetKit

enum WidgetDataStore {
    static let appGroupIdentifier = "group.pl.novydev.librussync"
    private static let eventsKey = "widgetUpcomingEvents"

    static func save(events: [AgendaEvent]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: eventsKey)
        defaults.set(Date(), forKey: "widgetLastUpdated")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadUpcomingEvents() -> [AgendaEvent] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: eventsKey),
              let events = try? JSONDecoder().decode([AgendaEvent].self, from: data) else { return [] }
        return events.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate }
    }
}
