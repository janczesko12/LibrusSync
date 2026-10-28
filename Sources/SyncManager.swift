import Foundation
import Combine
import BackgroundTasks

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published private(set) var status = "Połącz swoje konto Librus"
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var recentEvents: [AgendaEvent] = []
    @Published private(set) var isLibrusConnected = false
    @Published private(set) var librusDisplayName: String?
    @Published private(set) var calendarChoices: [AppleCalendarChoice] = []
    @Published private(set) var selectedCalendarIdentifier: String?

    private let defaults = UserDefaults.standard
    private let client = LibrusClient.shared
    private let writer = CalendarWriter.shared

    private init() {
        lastSync = defaults.object(forKey: "lastSuccessfulSync") as? Date
        if let data = defaults.data(forKey: "recentAgendaEvents"),
           let decoded = try? JSONDecoder().decode([AgendaEvent].self, from: data) { recentEvents = decoded }
        isLibrusConnected = KeychainStore.read(key: "librusLogin") != nil && KeychainStore.read(key: "librusPassword") != nil
        librusDisplayName = defaults.string(forKey: "librusDisplayName")
        status = isLibrusConnected ? "Konto Librus zapisane" : "Połącz swoje konto Librus"
        refreshCalendarState()
    }

    func connectLibrus(login: String, password: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        status = "Łączenie z Librus Synergia…"
        defer { isSyncing = false }
        do {
            let cleanedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
            let snapshot = try await client.connect(login: cleanedLogin, password: password)
            guard KeychainStore.save(cleanedLogin, key: "librusLogin"),
                  KeychainStore.save(password, key: "librusPassword") else {
                errorMessage = "Nie udało się bezpiecznie zapisać danych w pęku kluczy iOS."
                status = "Błąd bezpiecznego zapisu"
                return
            }
            isLibrusConnected = true
            librusDisplayName = snapshot.displayName
            defaults.set(snapshot.displayName, forKey: "librusDisplayName")
            _ = await LocalNotificationService.requestAuthorization()
            await apply(snapshot)
        } catch {
            errorMessage = error.localizedDescription
            status = "Nie udało się połączyć z Librusem"
        }
    }

    func synchronizeNow() async {
        guard !isSyncing else { return }
        guard let login = KeychainStore.read(key: "librusLogin"),
              let password = KeychainStore.read(key: "librusPassword") else {
            errorMessage = "Najpierw połącz konto Librus Synergia."
            status = "Konto niepołączone"
            isLibrusConnected = false
            return
        }
        isSyncing = true
        errorMessage = nil
        status = "Pobieram aktualny terminarz…"
        BackgroundRefreshScheduler.shared.scheduleNext()
        defer { isSyncing = false }
        do {
            let snapshot = try await client.synchronize(login: login, password: password)
            librusDisplayName = snapshot.displayName
            defaults.set(snapshot.displayName, forKey: "librusDisplayName")
            await apply(snapshot)
        } catch {
            errorMessage = error.localizedDescription
            status = "Synchronizacja nieudana"
        }
    }

    func prepareAppleCalendar() async {
        do {
            try await writer.prepareAccessAndLoadCalendars()
            refreshCalendarState()
            errorMessage = nil
            status = "Kalendarz Apple połączony"
        } catch {
            errorMessage = error.localizedDescription
            status = "Kalendarz Apple niedostępny"
        }
    }

    func selectCalendar(_ identifier: String) {
        writer.selectCalendar(identifier: identifier)
        refreshCalendarState()
    }

    func disconnectLibrus() {
        KeychainStore.delete(key: "librusLogin")
        KeychainStore.delete(key: "librusPassword")
        client.clearSession()
        defaults.removeObject(forKey: "librusDisplayName")
        defaults.removeObject(forKey: "knownEventFingerprints")
        defaults.removeObject(forKey: "hasCompletedInitialImport")
        isLibrusConnected = false
        librusDisplayName = nil
        errorMessage = nil
        status = "Konto Librus odłączone"
    }

    /// Ask for notification and calendar permission on the first app launch.
    /// iOS only shows each system prompt while its permission is not determined.
    func requestPermissionsOnLaunch() async {
        _ = await LocalNotificationService.requestAuthorization()
        do {
            try await writer.prepareAccessAndLoadCalendars()
            refreshCalendarState()
        } catch {
            // Keep the app usable if the user declines; the calendar card remains
            // available so the user can try again or change access in iOS Settings.
            refreshCalendarState()
        }
    }

    /// Called whenever the app becomes active. iOS does not expose a reliable
    /// callback for every device unlock; this runs when the app returns to the foreground.
    func appBecameActive() async {
        guard isLibrusConnected else { return }

        // If notifications have not been configured yet, ask for permission.
        _ = await LocalNotificationService.requestAuthorization()

        // Avoid repeated requests if the app briefly becomes active multiple times.
        let minimumInterval: TimeInterval = 5 * 60
        if lastSync == nil || Date().timeIntervalSince(lastSync!) >= minimumInterval {
            await synchronizeNow()
        } else {
            BackgroundRefreshScheduler.shared.scheduleNext()
        }
    }

    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        BackgroundRefreshScheduler.shared.scheduleNext()
        let operation = Task { @MainActor in
            await self.synchronizeNow()
            task.setTaskCompleted(success: self.errorMessage == nil)
        }
        task.expirationHandler = { operation.cancel() }
    }

    private func apply(_ snapshot: LibrusSnapshot) async {
        do {
            try await writer.prepareAccessAndLoadCalendars()
            refreshCalendarState()
            let prior = defaults.dictionary(forKey: "knownEventFingerprints") as? [String: String] ?? [:]
            let isFirstSync = !defaults.bool(forKey: "hasCompletedInitialImport")
            var next = prior
            var added = 0
            var changed = 0

            for item in snapshot.events {
                let fingerprint = item.fingerprint
                if let old = prior[item.uid] {
                    if old != fingerprint {
                        try writer.upsert(item)
                        next[item.uid] = fingerprint
                        changed += 1
                        await LocalNotificationService.notify(for: item, updated: true)
                    }
                } else {
                    try writer.upsert(item)
                    next[item.uid] = fingerprint
                    added += 1
                    await LocalNotificationService.notify(for: item, updated: false)
                }
            }

            defaults.set(next, forKey: "knownEventFingerprints")
            defaults.set(true, forKey: "hasCompletedInitialImport")
            defaults.set(Date(), forKey: "lastSuccessfulSync")
            defaults.set(try? JSONEncoder().encode(Array(snapshot.events.prefix(30))), forKey: "recentAgendaEvents")
            recentEvents = Array(snapshot.events.prefix(30))
            lastSync = Date()
            if snapshot.events.isEmpty {
                status = "Połączono • brak wydarzeń w terminarzu"
            } else if isFirstSync {
                status = "Pierwsza synchronizacja ukończona"
            } else if added == 0 && changed == 0 {
                status = "Wszystko aktualne"
            } else {
                status = "Nowe: \(added) • Zmienione: \(changed)"
            }
            errorMessage = nil
            BackgroundRefreshScheduler.shared.scheduleNext()
        } catch {
            errorMessage = error.localizedDescription
            status = "Połączono, ale synchronizacja kalendarza nie powiodła się"
        }
    }

    private func refreshCalendarState() {
        calendarChoices = writer.calendars
        selectedCalendarIdentifier = writer.selectedCalendarIdentifier
    }
}
