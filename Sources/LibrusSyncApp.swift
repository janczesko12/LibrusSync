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
        guard let login = KeychainStore.read(key: "librusLogin"), !login.isEmpty,
              let password = KeychainStore.read(key: "librusPassword"), !password.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 45 * 60)
        do { try BGTaskScheduler.shared.submit(request) } catch { }
    }
}
