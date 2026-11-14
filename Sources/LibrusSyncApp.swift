import SwiftUI
import BackgroundTasks

@main
struct LibrusSyncApp: App {
    init() {
        BackgroundRefreshScheduler.shared.register()
        BackgroundRefreshScheduler.shared.scheduleNext()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class BackgroundRefreshScheduler {
    static let shared = BackgroundRefreshScheduler()
    static let identifier = "pl.novydev.librussync.refresh"
    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            SyncManager.shared.handleBackgroundTask(refreshTask)
        }
    }

    func scheduleNext() {
        // Keep a single pending request. Repeated foreground/background transitions
        // must not leave stale requests that can block later scheduling.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)

        guard let login = KeychainStore.read(key: "librusLogin"), !login.isEmpty,
              let password = KeychainStore.read(key: "librusPassword"), !password.isEmpty else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        request.requiresNetworkConnectivity = true
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("LibrusSync: nie udało się zaplanować odświeżania w tle: \(error.localizedDescription)")
        }
    }

    func cancelPending() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
    }
}
