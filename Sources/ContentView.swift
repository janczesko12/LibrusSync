import SwiftUI
import UIKit
import PDFKit

struct ContentView: View {
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var appUpdateChecker = AppUpdateChecker()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showAppUpdateAlert = false
    @State private var login = KeychainStore.read(key: "librusLogin") ?? ""
    @State private var password = KeychainStore.read(key: "librusPassword") ?? ""
    @State private var showDisconnectConfirmation = false
    @State private var showNotificationTestAlert = false
    @State private var didCopyWidgetCode = false
    @State private var notificationTestTitle = "Test powiadomień"
    @State private var notificationTestMessage = ""
    @State private var eventSearch = ""
    @State private var eventFilter = "Wszystkie"
    @AppStorage("reminderWeekBefore") private var reminderWeekBefore = false
    @AppStorage("reminderTwoDays") private var reminderTwoDays = true
    @AppStorage("reminderSameDay") private var reminderSameDay = false
    @AppStorage("reminderAdvanceHour") private var reminderAdvanceHour = 18
    @AppStorage("reminderSameDayHour") private var reminderSameDayHour = 7
    @AppStorage("reminderAssessmentsOnly") private var reminderAssessmentsOnly = false

    private let ink = Color(uiColor: .label)
    private let violet = Color(red: 0.38, green: 0.30, blue: 0.93)
    private let lilac = Color(red: 0.63, green: 0.48, blue: 0.98)

    var body: some View {
        TabView {
            homeTab
            timetableTab
            eventsTab
            cafeteriaTab
            remindersTab
            settingsTab
        }
        .tint(violet)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await appUpdateChecker.checkIfNeeded()
                    await syncManager.appBecameActive()
                }
            case .background:
                BackgroundRefreshScheduler.shared.scheduleNext()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .confirmationDialog("Odłączyć konto Librus?", isPresented: $showDisconnectConfirmation, titleVisibility: .visible) {
            Button("Odłącz konto", role: .destructive) {
                syncManager.disconnectLibrus()
                login = ""
                password = ""
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Dane logowania i lokalna sesja zostaną usunięte z tego urządzenia.")
        }
        .alert(notificationTestTitle, isPresented: $showNotificationTestAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notificationTestMessage)
        }
        .onChange(of: appUpdateChecker.shouldNotifyForRelease) { _, shouldNotify in
            if shouldNotify {
                showAppUpdateAlert = true
            }
        }
        .task {
            await appUpdateChecker.checkIfNeeded()
            await syncManager.requestPermissionsOnLaunch()
        }
    }

    private var homeTab: some View {
        NavigationStack {
            pageScrollView {
                topBar
                heroCard
                countdownCard
                weeklyOverview
                syncControl
            }
        }
        .alert("Dostępna aktualizacja LibrusSync", isPresented: $showAppUpdateAlert) {
            Button("Pobierz aktualizację") {
                if let url = appUpdateChecker.releasePageURL {
                    openURL(url)
                }
            }
            Button("Później", role: .cancel) {}
        } message: {
            Text("Masz wersję \(appUpdateChecker.currentVersion), a najnowsza to \(appUpdateChecker.latestVersion ?? "—"). Otwórz stronę wydania, aby pobrać IPA.")
        }
        .tabItem {
            Label("Start", systemImage: "house.fill")
        }
    }

    private var timetableTab: some View {
        TimetableView()
            .tabItem {
                Label("Plan lekcji", systemImage: "calendar.day.timeline.left")
            }
    }

    private var eventsTab: some View {
        NavigationStack {
            pageScrollView {
                upcomingSection
            }
        }
        .tabItem {
            Label("Wydarzenia", systemImage: "calendar")
        }
    }

    private var cafeteriaTab: some View {
        CafeteriaView()
            .tabItem {
                Label("Stołówka", systemImage: "fork.knife")
            }
    }

    private var remindersTab: some View {
        NavigationStack {
            pageScrollView {
                reminderSettings
                notificationTestControl
                reminderInfoCard
            }
        }
        .tabItem {
            Label("Przypomnienia", systemImage: "bell.badge.fill")
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            pageScrollView {
                integrationsSection
                widgetRemoteSection
                AppUpdateCard(checker: appUpdateChecker)
                backgroundNote
                footer
            }
        }
        .tabItem {
            Label("Ustawienia", systemImage: "gearshape.fill")
        }
    }

    private func pageScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background {
            LibrusScreenBackground(tint: violet)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var reminderInfoCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "clock.badge.checkmark")
                .font(.title3)
                .foregroundStyle(violet)
                .frame(width: 38, height: 38)
                .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Przypomnienia na urządzeniu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Alerty są planowane lokalnie. iOS może ograniczać odświeżanie w tle, ale zaplanowane powiadomienia mogą pojawić się bez otwierania aplikacji.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var topBar: some View {
        HStack(spacing: 13) {
            Image("AppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: violet.opacity(0.18), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text("TWÓJ SZKOLNY ASYSTENT")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(violet)
                Text("LibrusSync")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                Text("Wszystko szkolne. W jednym miejscu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(spacing: 5) {
                Circle()
                    .fill(syncManager.isSyncing ? Color.orange : (syncManager.isLibrusConnected ? Color.green : Color.gray))
                    .frame(width: 9, height: 9)
                    .shadow(color: (syncManager.isSyncing ? Color.orange : (syncManager.isLibrusConnected ? Color.green : Color.gray)).opacity(0.45), radius: 5)
                Text(syncManager.isSyncing ? "SYNC" : (syncManager.isLibrusConnected ? "ONLINE" : "OFFLINE"))
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
        }
        .padding(.vertical, 3)
    }

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.25),
                        Color(red: 0.22, green: 0.20, blue: 0.61),
                        Color(red: 0.39, green: 0.30, blue: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle().fill(.white.opacity(0.07)).frame(width: 200, height: 200).offset(x: 75, y: -95)
            Circle().stroke(.white.opacity(0.13), lineWidth: 1).frame(width: 148, height: 148).offset(x: 40, y: -42)

            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar.badge.clock")
                        Text("TWÓJ SZKOLNY TYDZIEŃ")
                    }
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.05)
                    .foregroundStyle(.white.opacity(0.87))
                    Spacer()
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan lekcji")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Wszystkie zajęcia, sale i zastępstwa w jednym widoku.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    timetableMetric(value: "(selectedLessons.count)", label: "LEKCJI", symbol: "list.number")
                    timetableMetric(value: "(selectedLessons.filter { $0.isSubstitution }.count)", label: "ZASTĘPSTW", symbol: "arrow.triangle.2.circlepath")
                    timetableMetric(value: selectedDate.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pl_PL"))), label: "WYBRANY DZIEŃ", symbol: "calendar")
                }
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: violet.opacity(0.25), radius: 22, x: 0, y: 12)
    }

    private func timetableMetric(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 1))
    }

    private var weekPicker: some View {
        HStack(spacing: 12) {
            Button {
                moveWeek(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(violet)
                    .frame(width: 42, height: 42)
                    .background(violet.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Poprzedni tydzień")

            VStack(spacing: 3) {
                Text("WYBRANY TYDZIEŃ")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Text(weekRangeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)

            Button {
                moveWeek(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(violet)
                    .frame(width: 42, height: 42)
                    .background(violet.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Następny tydzień")

            Button {
                Task { await loadTimetable(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [violet, lilac], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Odśwież plan lekcji")
        }
        .padding(12)
        .lsSurface(21)
    }

    private var dayPicker: some View {
        HStack(spacing: 8) {
            ForEach(weekDates, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                let today = Calendar.current.isDateInToday(date)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 7) {
                        Text(shortWeekday(date))
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Circle()
                            .fill(selected ? .white : (dateHasSubstitution(date) ? Color.orange : (today ? violet : .clear)))
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(selected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [violet, lilac], startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? .clear : Color.primary.opacity(0.045), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullDate(date))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func dateHasSubstitution(_ date: Date) -> Bool {
        days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?
            .lessons.contains(where: \.isSubstitution) ?? false
    }

    private var selectedDayHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fullDate(selectedDate))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(Calendar.current.isDateInToday(selectedDate) ? "Twój plan na dzisiaj" : "Plan na wybrany dzień")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedLessons.contains(where: { $0.isSubstitution }) {
                Label("ZASTĘPSTWA", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.35)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            } else if Calendar.current.isDateInToday(selectedDate) {
                Text("DZISIAJ")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(violet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(violet.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var lessonContent: some View {
        if isLoading && days.isEmpty {
            VStack(spacing: 12) {
                ProgressView().tint(violet)
                Text("Pobieram plan z Librusa…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if let errorMessage, days.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: syncManager.isLibrusConnected ? "calendar.badge.exclamationmark" : "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(violet)
                Text(syncManager.isLibrusConnected ? "Plan lekcji niedostępny" : "Połącz konto Librus")
                    .font(.headline)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await loadTimetable(force: true) }
                } label: {
                    Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(violet)
                .disabled(isLoading)
            }
            .padding(23)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if selectedLessons.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.orange)
                Text("Brak lekcji")
                    .font(.headline)
                Text("Na ten dzień nie ma zajęć w opublikowanym planie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(25)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 10) {
                ForEach(selectedLessons) { lesson in
                    lessonCard(lesson)
                }
            }
        }
    }

    private func lessonCard(_ lesson: LessonPeriod) -> some View {
        let substitution = lesson.isSubstitution
        let current = isCurrentLesson(lesson)
        let accent = substitution ? Color.orange : (current ? Color.green : violet)

        return HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(String(format: "%02d", lesson.number))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text("LEKCJA")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 55, height: 66)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(accent.opacity(0.13), lineWidth: 1))

            VStack(alignment: .leading, spacing: 7) {
                Text(lesson.subject)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if substitution {
                        Label("ZASTĘPSTWO", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.35)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.13), in: Capsule())
                    }
                    if current {
                        Label("TERAZ", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.35)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.green, in: Capsule())
                    }
                }

                if !lesson.teacherAndRoom.isEmpty {
                    Label(lesson.teacherAndRoom, systemImage: "person.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 4) {
                Text(lesson.startTime.isEmpty ? "—" : lesson.startTime)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(lesson.endTime.isEmpty ? "" : lesson.endTime)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Capsule()
                    .fill(accent.opacity(0.6))
                    .frame(width: 27, height: 3)
                    .padding(.top, 3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .secondarySystemGroupedBackground),
                            accent.opacity(substitution || current ? 0.10 : 0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 5)
                .padding(.vertical, 13)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(substitution || current ? 0.27 : 0.07), lineWidth: substitution || current ? 1.3 : 1)
        }
        .shadow(color: accent.opacity(substitution || current ? 0.08 : 0.025), radius: 12, x: 0, y: 5)
        .animation(.snappy(duration: 0.22), value: current)
        .animation(.snappy(duration: 0.22), value: substitution)
    }

    private func isCurrentLesson(_ lesson: LessonPeriod) -> Bool {
        guard Calendar.current.isDateInToday(selectedDate) else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        guard let startClock = formatter.date(from: lesson.startTime),
              let endClock = formatter.date(from: lesson.endTime) else { return false }
        let calendar = Calendar.current
        let now = Date()
        let startParts = calendar.dateComponents([.hour, .minute], from: startClock)
        let endParts = calendar.dateComponents([.hour, .minute], from: endClock)
        guard let start = calendar.date(bySettingHour: startParts.hour ?? 0, minute: startParts.minute ?? 0, second: 0, of: selectedDate),
              let end = calendar.date(bySettingHour: endParts.hour ?? 0, minute: endParts.minute ?? 0, second: 0, of: selectedDate) else { return false }
        return now >= start && now < end
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(violet)
            Text("Plan jest pobierany z opublikowanego widoku Librus Synergia. Jeśli szkoła nie udostępnia planu uczniom, aplikacja pokaże informację zamiast wymyślonych lekcji.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 3)
    }

    private var weekRangeTitle: String {
        let end = Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }

    private func shortWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date).capitalized
    }

    private func moveWeek(_ offset: Int) {
        guard let newWeek = Calendar.current.date(byAdding: .day, value: 7 * offset, to: weekStart) else { return }
        weekStart = newWeek
        selectedDate = newWeek
        days = []
        errorMessage = nil
        didLoad = false
        Task { await loadTimetable(force: false) }
    }

    @MainActor
    private func loadTimetable(force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        if !force, let cached = UserDefaults.standard.data(forKey: cacheKey),
           let cachedDays = try? JSONDecoder().decode([TimetableDay].self, from: cached) {
            days = cachedDays
        }

        guard syncManager.isLibrusConnected else {
            if days.isEmpty {
                errorMessage = TimetableLoadError.accountNotConnected.localizedDescription
            }
            return
        }

        do {
            let freshDays = try await syncManager.fetchTimetable(weekStarting: weekStart)
            let previousDays: [TimetableDay]? = UserDefaults.standard.data(forKey: cacheKey)
                .flatMap { try? JSONDecoder().decode([TimetableDay].self, from: $0) }
            days = freshDays
            if let previousDays {
                func lessonFingerprint(_ lesson: LessonPeriod) -> String {
                    "\(lesson.id)|\(lesson.subject)|\(lesson.teacherAndRoom)|\(lesson.startTime)|\(lesson.endTime)|\(lesson.isSubstitution)"
                }
                let oldSubstitutions = Set(previousDays.flatMap(\.lessons).filter(\.isSubstitution).map(lessonFingerprint))
                let newSubstitutions = freshDays.flatMap(\.lessons)
                    .filter(\.isSubstitution)
                    .filter { !oldSubstitutions.contains(lessonFingerprint($0)) }
                if !newSubstitutions.isEmpty {
                    let first = newSubstitutions[0]
                    await LocalNotificationService.notify(
                        title: "Dodano zastępstwo",
                        body: "\(first.subject) • \(newSubstitutions.count) nowe/zmienione zastępstwa w planie. Sprawdź szczegóły w LibrusSync.",
                        identifier: "substitution-\(cacheKey)-\(newSubstitutions.map(\.id).sorted().joined(separator: "-"))"
                    )
                } else if previousDays != freshDays {
                    await LocalNotificationService.notify(
                        title: "Zmieniono plan lekcji",
                        body: "LibrusSync wykrył aktualizację planu na wybrany tydzień.",
                        identifier: "timetable-\(cacheKey)-\(Int(Date().timeIntervalSince1970))"
                    )
                }
            }
            if let encoded = try? JSONEncoder().encode(freshDays) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            errorMessage = nil
        } catch {
            if days.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Nie udało się odświeżyć danych. Wyświetlam ostatnio zapisany plan."
            }
        }
    }
}


// MARK: - LibrusSync visual system

private struct LibrusScreenBackground: View {
    let tint: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [tint.opacity(0.075), .clear, Color.blue.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(tint.opacity(0.075))
                .frame(width: 250, height: 250)
                .blur(radius: 58)
                .offset(x: 112, y: -125)
            Circle()
                .fill(Color.blue.opacity(0.035))
                .frame(width: 220, height: 220)
                .blur(radius: 64)
                .offset(x: -180, y: 430)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private extension View {
    func lsSurface(_ radius: CGFloat = 23) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.62), Color.primary.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.045), radius: 15, x: 0, y: 7)
    }
}
