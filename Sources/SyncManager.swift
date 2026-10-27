import Foundation
import Combine
import BackgroundTasks

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published private(set) var status = "Gotowy do synchronizacji"
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var recentEvents: [AgendaEvent] = []

    private let defaults = UserDefaults.standard
    private let client = CalendarFeedClient()
    private let writer = CalendarWriter.shared

    private init() {
        lastSync = defaults.object(forKey: "lastSuccessfulSync") as? Date
        if let data = defaults.data(forKey: "recentAgendaEvents"),
           let decoded = try? JSONDecoder().decode([AgendaEvent].self, from: data) {
            recentEvents = decoded
        }
        status = KeychainStore.read(key: "calendarFeedURL") == nil
            ? "Dodaj źródło kalendarza"
            : "Gotowy do synchronizacji"
    }

    func syncNow(feedURL: String) async {
        let cleaned = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "Najpierw dodaj adres źródła kalendarza (.ics)."
            status = "Brak źródła"
            return
        }
        guard KeychainStore.save(cleaned, key: "calendarFeedURL") else {
            errorMessage = "Nie udało się bezpiecznie zapisać adresu w pęku kluczy iOS."
            status = "Błąd konfiguracji"
            return
        }
        BackgroundRefreshScheduler.shared.scheduleNext()

        isSyncing = true
        errorMessage = nil
        status = "Pobieram terminarz…"
        defer { isSyncing = false }

        do {
            let events = try await client.fetchEvents(from: cleaned)
            let prior = defaults.dictionary(forKey: "knownEventFingerprints") as? [String: String] ?? [:]
            let isFirstSync = !defaults.bool(forKey: "hasCompletedInitialImport")

            if !events.isEmpty {
                try await writer.requestAccess()
            }

            var next = prior
            var additions = 0
            var changes = 0

            for item in events {
                let fingerprint = item.fingerprint
                if let oldFingerprint = prior[item.uid] {
                    if oldFingerprint != fingerprint {
                        try writer.upsert(item)
                        next[item.uid] = fingerprint
                        changes += 1
                        if !isFirstSync {
                            await LocalNotificationService.notify(for: item, updated: true)
                        }
                    }
                } else {
                    try writer.upsert(item)
                    next[item.uid] = fingerprint
                    additions += 1
                    if !isFirstSync {
                        await LocalNotificationService.notify(for: item, updated: false)
                    }
                }
            }

            defaults.set(next, forKey: "knownEventFingerprints")
            defaults.set(true, forKey: "hasCompletedInitialImport")
            defaults.set(Date(), forKey: "lastSuccessfulSync")
            defaults.set(try? JSONEncoder().encode(Array(events.prefix(20))), forKey: "recentAgendaEvents")

            recentEvents = Array(events.prefix(20))
            lastSync = Date()
            if isFirstSync {
                status = "Pierwszy import ukończony"
            } else if additions == 0 && changes == 0 {
                status = "Brak zmian"
            } else {
                status = "Dodano: \(additions), zmieniono: \(changes)"
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "Synchronizacja nieudana"
        }
    }

    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        BackgroundRefreshScheduler.shared.scheduleNext()
        let operation = Task { @MainActor in
            let source = KeychainStore.read(key: "calendarFeedURL") ?? ""
            await self.syncNow(feedURL: source)
            task.setTaskCompleted(success: self.errorMessage == nil)
        }
        task.expirationHandler = {
            operation.cancel()
        }
    }
}