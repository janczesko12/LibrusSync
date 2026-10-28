import SwiftUI
import WidgetKit

struct LibrusSyncWidgetEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
}

struct LibrusSyncWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibrusSyncWidgetEntry {
        let eventDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        return LibrusSyncWidgetEntry(date: Date(), events: [
            AgendaEvent(uid: "preview", title: "Sprawdzian z matematyki",
                        startDate: eventDate, endDate: eventDate.addingTimeInterval(3600),
                        notes: "Kategoria: Sprawdzian")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (LibrusSyncWidgetEntry) -> Void) {
        completion(LibrusSyncWidgetEntry(date: Date(), events: WidgetDataStore.loadUpcomingEvents()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibrusSyncWidgetEntry>) -> Void) {
        let entry = LibrusSyncWidgetEntry(date: Date(), events: WidgetDataStore.loadUpcomingEvents())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct LibrusSyncUpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibrusSyncWidgetEntry

    private var nextEvent: AgendaEvent? {
        entry.events.first(where: \.isAssessment) ?? entry.events.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.28, green: 0.22, blue: 0.78), Color(red: 0.58, green: 0.36, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                    Text("LIBRUSSYNC").tracking(1.1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

                if let event = nextEvent {
                    Text(event.isAssessment ? "NAJBLIŻSZY SPRAWDZIAN" : "NAJBLIŻSZE WYDARZENIE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(event.title)
                        .font(.system(size: family == .systemSmall ? 16 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(family == .systemSmall ? 3 : 2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    HStack(alignment: .lastTextBaseline) {
                        Text(event.countdownLabel)
                            .font(.system(size: family == .systemSmall ? 18 : 22, weight: .heavy, design: .rounded))
                        Spacer(minLength: 4)
                        Text(event.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).day().month(.abbreviated)))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                } else {
                    Spacer(minLength: 0)
                    Text("Brak nadchodzących wydarzeń")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Otwórz aplikację i zsynchronizuj Librusa.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            Color(red: 0.30, green: 0.24, blue: 0.82)
        }
    }
}

struct LibrusSyncUpcomingWidget: Widget {
    let kind = "LibrusSyncUpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibrusSyncWidgetProvider()) { entry in
            LibrusSyncUpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Najbliższy sprawdzian")
        .description("Odliczanie do sprawdzianu lub najbliższego wydarzenia z Librusa.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LibrusSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        LibrusSyncUpcomingWidget()
    }
}
