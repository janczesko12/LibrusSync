import SwiftUI
import WidgetKit
import AppIntents

struct LibrusSyncWidgetEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
}

struct LibrusSyncWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Konfiguracja widżetu LibrusSync"
    static var description = IntentDescription("Wklej kod z aplikacji LibrusSync, aby widżet pobierał prywatne wydarzenia.")

    @Parameter(title: "Kod widżetu", description: "Wklej kod skopiowany w aplikacji LibrusSync.")
    var accessCode: String

    init() {
        accessCode = ""
    }
}

struct LibrusSyncWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LibrusSyncWidgetEntry {
        LibrusSyncWidgetEntry(date: Date(), events: Self.previewEvents)
    }

    func snapshot(for configuration: LibrusSyncWidgetConfigurationIntent, in context: Context) async -> LibrusSyncWidgetEntry {
        if context.isPreview {
            return LibrusSyncWidgetEntry(date: Date(), events: Self.previewEvents)
        }
        let events = await WidgetRemoteStore.loadUpcomingEvents(accessCode: configuration.accessCode)
        return LibrusSyncWidgetEntry(date: Date(), events: events)
    }

    func timeline(for configuration: LibrusSyncWidgetConfigurationIntent, in context: Context) async -> Timeline<LibrusSyncWidgetEntry> {
        let events = await WidgetRemoteStore.loadUpcomingEvents(accessCode: configuration.accessCode)
        let entry = LibrusSyncWidgetEntry(date: Date(), events: events)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
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
                LinearGradient(
                    colors: [Color(red: 0.28, green: 0.22, blue: 0.78), Color(red: 0.58, green: 0.36, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var homeScreenView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                Text("LIBRUSSYNC").tracking(0.8)
                Spacer(minLength: 0)
            }
            .font(.system(size: family == .systemSmall ? 9 : 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let event = nextEvent {
                Text(event.isAssessment
                     ? (family == .systemSmall ? "SPRAWDZIAN" : "NAJBLIŻSZY SPRAWDZIAN")
                     : (family == .systemSmall ? "WYDARZENIE" : "NAJBLIŻSZE WYDARZENIE"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(event.title)
                    .font(.system(size: family == .systemSmall ? 15 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 3 : 2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.countdownLabel)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(.white)
                        Text(event.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).day().month(.abbreviated)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(event.countdownLabel)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        Text(event.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).day().month(.abbreviated)))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(.white)
                }
            } else {
                Spacer(minLength: 0)
                Text("Brak nadchodzących wydarzeń")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Otwórz LibrusSync i zsynchronizuj Librusa.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemSmall ? 12 : 16)
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

    @ViewBuilder
    private var inlineLockScreenView: some View {
        if let event = nextEvent {
            let category = event.isAssessment ? "Sprawdzian" : "Wydarzenie"
            Text("\(category): \(event.title) — \(event.countdownLabel)")
        } else {
            Text("LibrusSync: brak nadchodzących wydarzeń")
        }
    }
}

struct LibrusSyncUpcomingWidget: Widget {
    let kind = "LibrusSyncUpcomingWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LibrusSyncWidgetConfigurationIntent.self, provider: LibrusSyncWidgetProvider()) { entry in
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
