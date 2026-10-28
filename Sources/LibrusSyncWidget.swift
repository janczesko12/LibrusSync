import SwiftUI
import WidgetKit

struct LibrusSyncWidgetEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
}

struct LibrusSyncWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibrusSyncWidgetEntry {
        LibrusSyncWidgetEntry(date: Date(), events: Self.previewEvents)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibrusSyncWidgetEntry) -> Void) {
        // The widget gallery asks for a snapshot before the user has synced any data.
        // Always give it something useful to preview instead of an empty card.
        let events = context.isPreview ? Self.previewEvents : WidgetDataStore.loadUpcomingEvents()
        completion(LibrusSyncWidgetEntry(date: Date(), events: events))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibrusSyncWidgetEntry>) -> Void) {
        let entry = LibrusSyncWidgetEntry(date: Date(), events: WidgetDataStore.loadUpcomingEvents())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private static var previewEvents: [AgendaEvent] {
        let eventDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        return [
            AgendaEvent(
                uid: "preview",
                title: "Sprawdzian z matematyki",
                startDate: eventDate,
                endDate: eventDate.addingTimeInterval(3600),
                notes: "Kategoria: Sprawdzian"
            )
        ]
    }
}

struct LibrusSyncUpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibrusSyncWidgetEntry

    private var nextEvent: AgendaEvent? {
        entry.events.first(where: \.isAssessment) ?? entry.events.first
    }

    private var daysUntilNextEvent: Int {
        guard let event = nextEvent else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: event.startDate)
        return max(0, calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLockScreenView
            case .accessoryRectangular:
                rectangularLockScreenView
            case .accessoryInline:
                inlineLockScreenView
            default:
                homeScreenView
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Color.clear
            default:
                Color(red: 0.30, green: 0.24, blue: 0.82)
            }
        }
    }

    private var homeScreenView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.28, green: 0.22, blue: 0.78), Color(red: 0.58, green: 0.36, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
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
                    Text("Otwórz LibrusSync i zsynchronizuj Librusa.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
    }

    private var circularLockScreenView: some View {
        VStack(spacing: 1) {
            Image(systemName: nextEvent?.isAssessment == true ? "pencil.and.list.clipboard" : "calendar")
                .font(.caption2)
            if let event = nextEvent {
                Text("\(daysUntilNextEvent)")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text(daysUntilNextEvent == 1 ? "dzień" : "dni")
                    .font(.system(size: 9, weight: .semibold))
            } else {
                Text("—").font(.headline)
                Text("brak").font(.system(size: 9, weight: .semibold))
            }
        }
        .widgetAccentable()
    }

    private var rectangularLockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nextEvent?.isAssessment == true ? "NAJBLIŻSZY SPRAWDZIAN" : "LIBRUSSYNC")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if let event = nextEvent {
                Text(event.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.countdownLabel)
                    Text("·")
                    Text(event.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).day().month(.abbreviated)))
                }
                .font(.caption2)
            } else {
                Text("Brak nadchodzących wydarzeń")
                    .font(.headline)
                    .lineLimit(1)
            }
        }
    }

    private var inlineLockScreenView: some View {
        if let event = nextEvent {
            Text("\(event.isAssessment ? "Sprawdzian" : "Wydarzenie"): \(event.title) — \(event.countdownLabel)")
        } else {
            Text("LibrusSync: brak nadchodzących wydarzeń")
        }
    }
}

struct LibrusSyncUpcomingWidget: Widget {
    let kind = "LibrusSyncUpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibrusSyncWidgetProvider()) { entry in
            LibrusSyncUpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("LibrusSync — sprawdziany")
        .description("Najbliższy sprawdzian i odliczanie na ekranie początkowym lub blokady.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct LibrusSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        LibrusSyncUpcomingWidget()
    }
}
