import SwiftUI
import UIKit
import PDFKit

struct ContentView: View {
    @StateObject private var syncManager = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase
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
            eventsTab
            cafeteriaTab
            remindersTab
            settingsTab
        }
        .tint(violet)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await syncManager.appBecameActive() }
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
        .task {
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
        .tabItem {
            Label("Start", systemImage: "house.fill")
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
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
        HStack(spacing: 11) {
            ZStack {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 45, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("LibrusSync").font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(ink)
                Text("Twój szkolny plan w jednym miejscu").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(syncManager.errorMessage == nil ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(syncManager.isSyncing ? "Pracuję" : "Gotowy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.27, green: 0.23, blue: 0.76), Color(red: 0.47, green: 0.31, blue: 0.91), Color(red: 0.61, green: 0.40, blue: 0.93)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle().fill(.white.opacity(0.09)).frame(width: 180, height: 180).offset(x: 45, y: -65)
            Circle().stroke(.white.opacity(0.13), lineWidth: 1).frame(width: 138, height: 138).offset(x: 20, y: 5)
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("TWOJA SYNCHRONIZACJA", systemImage: "sparkles").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }
                Text(syncManager.isLibrusConnected ? "Cześć, \(displayFirstName)!" : "Koniec z ręcznym przepisywaniem.")
                    .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(syncManager.isLibrusConnected
                     ? "Librus Synergia jest połączony. Nowe wpisy mogą trafiać do Kalendarza Apple."
                     : "Połącz dziennik i Kalendarz Apple, a LibrusSync zajmie się resztą.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.84)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    metricPill(value: "\(syncManager.recentEvents.count)", label: "wydarzeń")
                    metricPill(value: syncManager.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", label: "ostatnia sync.")
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: violet.opacity(0.2), radius: 18, x: 0, y: 9)
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(violet)
                    .frame(width: 42, height: 42)
                    .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Odliczanie do sprawdzianu")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Na podstawie wpisów wykrytych w Librusie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let event = nextAssessment {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                        Text("\(event.dateLabel) · \(event.timeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(event.countdownLabel)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(LinearGradient(colors: [violet, lilac], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
            } else {
                Text("Gdy LibrusSync wykryje wpis opisany jako sprawdzian, kartkówka, test lub praca klasowa, zobaczysz tutaj odliczanie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var nextAssessment: AgendaEvent? {
        syncManager.recentEvents.first(where: { $0.isAssessment })
    }

    private var nextSevenDaysEvents: [AgendaEvent] {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: startOfToday) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        return syncManager.recentEvents
            .filter { $0.startDate < end && $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
    }

    private var busiestUpcomingDay: (date: Date, count: Int)? {
        let grouped = Dictionary(grouping: nextSevenDaysEvents, by: { Calendar.current.startOfDay(for: $0.startDate) })
        guard let busiest = grouped.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return (date: busiest.key, count: busiest.value.count)
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(violet)
                    .frame(width: 42, height: 42)
                    .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Co mnie czeka?")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Podsumowanie najbliższych 7 dni")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                dashboardMetric(value: "\(nextSevenDaysEvents.count)", label: "Wydarzenia", symbol: "calendar")
                dashboardMetric(value: "\(nextSevenDaysEvents.filter(\.isAssessment).count)", label: "Sprawdziany", symbol: "graduationcap.fill")
                dashboardMetric(
                    value: busiestUpcomingDay.map { $0.date.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).weekday(.abbreviated).day()) } ?? "—",
                    label: "Najbardziej zajęty dzień",
                    symbol: "chart.bar.fill"
                )
            }

            if nextSevenDaysEvents.isEmpty {
                Text("Brak nadchodzących wydarzeń w tym tygodniu. Po synchronizacji zobaczysz tu najbliższe terminy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(nextSevenDaysEvents.prefix(3).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 10) {
                            Image(systemName: event.isAssessment ? "graduationcap.fill" : "calendar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(event.isAssessment ? violet : Color.blue)
                                .frame(width: 34, height: 34)
                                .background((event.isAssessment ? violet : Color.blue).opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                Text(event.startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).weekday(.wide).day().month(.abbreviated)) + " · " + event.timeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 3)
                            Text(event.countdownLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(violet)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 9)
                        if index < min(nextSevenDaysEvents.count, 3) - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dashboardMetric(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(violet)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(10)
        .background(violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var reminderSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Przypomnienia", subtitle: "Wybierz, kiedy iPhone ma Ci przypominać")
            VStack(spacing: 0) {
                reminderToggle(
                    title: "Tydzień wcześniej",
                    subtitle: "7 dni przed wydarzeniem",
                    symbol: "calendar",
                    isOn: $reminderWeekBefore
                )
                Divider().padding(.leading, 56)
                reminderToggle(
                    title: "Dwa dni wcześniej",
                    subtitle: "Domyślne przypomnienie",
                    symbol: "calendar.badge.clock",
                    isOn: $reminderTwoDays
                )
                Divider().padding(.leading, 56)
                reminderToggle(
                    title: "W dniu wydarzenia",
                    subtitle: "O wybranej godzinie, jeśli nie jest za późno",
                    symbol: "bell.badge",
                    isOn: $reminderSameDay
                )
                Divider().padding(.leading, 56)
                reminderToggle(
                    title: "Tylko sprawdziany i kartkówki",
                    subtitle: "Pomiń zwykłe wydarzenia w planowanych przypomnieniach",
                    symbol: "graduationcap.fill",
                    isOn: $reminderAssessmentsOnly
                )
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 10) {
                Picker("Godzina wcześniejszych przypomnień", selection: $reminderAdvanceHour) {
                    ForEach(15...22, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                Picker("Godzina przypomnienia w dniu wydarzenia", selection: $reminderSameDayHour) {
                    ForEach(5...10, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Powiadomienia są planowane lokalnie na telefonie. Zmiana ustawień przelicza alerty. iOS może ograniczyć działanie aplikacji w tle, ale wcześniej zaplanowane powiadomienia nie wymagają kolejnej synchronizacji.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: reminderWeekBefore) { _, _ in refreshReminderSchedule() }
        .onChange(of: reminderTwoDays) { _, _ in refreshReminderSchedule() }
        .onChange(of: reminderSameDay) { _, _ in refreshReminderSchedule() }
        .onChange(of: reminderAdvanceHour) { _, _ in refreshReminderSchedule() }
        .onChange(of: reminderSameDayHour) { _, _ in refreshReminderSchedule() }
        .onChange(of: reminderAssessmentsOnly) { _, _ in refreshReminderSchedule() }
    }

    private func reminderToggle(title: String, subtitle: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(violet)
                .frame(width: 34, height: 34)
                .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(violet)
        }
        .padding(.vertical, 12)
    }

    private func refreshReminderSchedule() {
        guard let data = UserDefaults.standard.data(forKey: "recentAgendaEvents"),
              let events = try? JSONDecoder().decode([AgendaEvent].self, from: data) else { return }
        Task { await LocalNotificationService.scheduleReminders(for: events) }
    }

    private func metricPill(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(value).font(.caption.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.13), in: Capsule())
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("Połączone usługi", subtitle: "Wszystko zostaje na Twoim iPhonie")
            VStack(spacing: 0) {
                librusCard
                Divider().padding(.leading, 68)
                appleCalendarCard
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
    }

    private var librusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                integrationIcon(symbol: "graduationcap.fill", colors: [Color(red: 0.94, green: 0.45, blue: 0.24), Color(red: 0.95, green: 0.64, blue: 0.28)])
                VStack(alignment: .leading, spacing: 4) {
                    Text("Librus Synergia").font(.subheadline.weight(.bold)).foregroundStyle(ink)
                    Text(syncManager.isLibrusConnected ? (syncManager.librusDisplayName ?? "Konto połączone") : "Zaloguj się danymi z dziennika")
                        .font(.caption).foregroundStyle(.secondary)
                    if syncManager.isLibrusConnected {
                        Label("Połączono", systemImage: "checkmark.circle.fill").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                Spacer()
                if syncManager.isLibrusConnected {
                    Button { showDisconnectConfirmation = true } label: {
                        Image(systemName: "ellipsis").font(.headline).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Opcje konta Librus")
                }
            }

            if !syncManager.isLibrusConnected {
                VStack(spacing: 9) {
                    TextField("Login do Librus Synergia", text: $login)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable).padding(13)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    SecureField("Hasło do Librus Synergia", text: $password)
                        .textContentType(.password).padding(13)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Button {
                        Task { await syncManager.connectLibrus(login: login, password: password) }
                    } label: {
                        HStack(spacing: 8) {
                            if syncManager.isSyncing { ProgressView().tint(.white) } else { Image(systemName: "lock.open.fill") }
                            Text(syncManager.isSyncing ? "Łączenie…" : "Połącz z Librusem")
                        }
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(LinearGradient(colors: [violet, lilac], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(syncManager.isSyncing || login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    Text("Dane logowania są przechowywane w Keychain na tym urządzeniu.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
    }

    private var appleCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                integrationIcon(symbol: "calendar", colors: [Color(red: 0.21, green: 0.66, blue: 0.98), Color(red: 0.24, green: 0.46, blue: 0.94)])
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kalendarz Apple").font(.subheadline.weight(.bold)).foregroundStyle(ink)
                    Text(syncManager.selectedCalendarIdentifier == nil ? "Wybierz kalendarz do synchronizacji" : (selectedCalendarTitle ?? "Kalendarz docelowy wybrany"))
                        .font(.caption).foregroundStyle(.secondary)
                    if syncManager.selectedCalendarIdentifier != nil {
                        Label("Gotowy do zapisu", systemImage: "checkmark.circle.fill").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                Spacer()
            }

            if !syncManager.calendarChoices.isEmpty {
                Picker("Zapisuj wydarzenia w", selection: Binding(
                    get: { syncManager.selectedCalendarIdentifier ?? "" },
                    set: { syncManager.selectCalendar($0) }
                )) {
                    ForEach(syncManager.calendarChoices) { calendar in
                        Text("\(calendar.title) · \(calendar.source)").tag(calendar.id)
                    }
                }
                .font(.subheadline).pickerStyle(.menu).padding(.horizontal, 12).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                Button { Task { await syncManager.prepareAppleCalendar() } } label: {
                    Label("Połącz Kalendarz Apple", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func integrationIcon(symbol: String, colors: [Color]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
        }
    }

    private var syncControl: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button { Task { await syncManager.synchronizeNow() } } label: {
                HStack(spacing: 10) {
                    if syncManager.isSyncing { ProgressView().tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath").font(.headline.weight(.bold)) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncManager.isSyncing ? "Synchronizuję…" : "Synchronizuj teraz").font(.headline.weight(.bold))
                        Text("Pobierz zmiany i zaktualizuj kalendarz").font(.caption).foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white).padding(17)
                .background(LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.23), Color(red: 0.22, green: 0.27, blue: 0.43)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSyncing || !syncManager.isLibrusConnected)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: syncManager.errorMessage == nil ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(syncManager.errorMessage == nil ? violet : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncManager.status).font(.subheadline.weight(.semibold))
                    if let message = syncManager.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(syncManager.lastSync.map { "Ostatnie sprawdzenie: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Połącz konto i uruchom pierwszą synchronizację.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.top, 2)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(violet)
                Text(syncManager.widgetDataStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
        }
    }

    private var notificationTestControl: some View {
        Button {
            Task {
                let result = await LocalNotificationService.sendTestNotification()
                notificationTestTitle = result.success ? "Test zaplanowany" : "Powiadomienia wymagają uwagi"
                notificationTestMessage = result.message
                showNotificationTestAlert = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(violet)
                    .frame(width: 42, height: 42)
                    .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Testuj powiadomienia")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Wyślij testowy alert na tego iPhone’a")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filteredUpcomingEvents: [AgendaEvent] {
        let normalizedQuery = eventSearch.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return syncManager.recentEvents.filter { event in
            let matchesFilter: Bool
            switch eventFilter {
            case "Sprawdziany":
                matchesFilter = event.isAssessment
            case "Pozostałe":
                matchesFilter = !event.isAssessment
            default:
                matchesFilter = true
            }
            let searchableText = "\(event.title) \(event.notes)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            return matchesFilter && (normalizedQuery.isEmpty || searchableText.contains(normalizedQuery))
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                sectionHeading("Inteligentny terminarz", subtitle: "Szukaj i filtruj wydarzenia z Librusa")
                Spacer()
                Text("\(filteredUpcomingEvents.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(violet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(violet.opacity(0.1), in: Capsule())
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Szukaj nazwy, przedmiotu lub notatki", text: $eventSearch)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !eventSearch.isEmpty {
                    Button {
                        eventSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("Filtr wydarzeń", selection: $eventFilter) {
                Text("Wszystkie").tag("Wszystkie")
                Text("Sprawdziany").tag("Sprawdziany")
                Text("Pozostałe").tag("Pozostałe")
            }
            .pickerStyle(.segmented)

            if filteredUpcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: syncManager.recentEvents.isEmpty ? "calendar.badge.clock" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 27))
                        .foregroundStyle(violet)
                    Text(syncManager.recentEvents.isEmpty ? "Na razie pusto" : "Brak pasujących wydarzeń")
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(syncManager.recentEvents.isEmpty
                         ? "Po połączeniu Librusa wydarzenia pojawią się tutaj."
                         : "Zmień filtr albo wyszukiwaną frazę, aby zobaczyć inne pozycje.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredUpcomingEvents.prefix(30).enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, accent: event.isAssessment ? violet : Color.blue)
                        if index < min(filteredUpcomingEvents.count, 30) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ink)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var widgetRemoteSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("Widżet na ekranie", subtitle: "Połącz widżet bez App Groups")
            VStack(alignment: .leading, spacing: 10) {
                Text("Kod konfiguracji")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                if syncManager.widgetShareCode.isEmpty {
                    Text("Nie udało się utworzyć kodu. Zamknij i uruchom aplikację ponownie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(syncManager.widgetShareCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        UIPasteboard.general.string = syncManager.widgetShareCode
                        didCopyWidgetCode = true
                    } label: {
                        Label(didCopyWidgetCode ? "Skopiowano kod" : "Kopiuj kod do widżetu",
                              systemImage: didCopyWidgetCode ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(violet)
                    Text("Dodaj lub edytuj widżet LibrusSync na ekranie iPhone’a, otwórz ustawienie „Kod widżetu” i wklej skopiowany kod.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Serwer przechowuje daty i treści nadchodzących wydarzeń oraz skróty kluczy dostępu — nie login ani hasło do Librusa. Nie udostępniaj kodu widżetu.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var backgroundNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "moon.zzz.fill").font(.title3).foregroundStyle(violet).frame(width: 35, height: 35)
                .background(violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Oszczędza baterię").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Text("Aplikacja nie działa w pętli. iOS wybudza ją w dogodnym momencie, dlatego synchronizacja w tle nie ma stałej godziny.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(violet.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Image(systemName: "lock.shield.fill")
            Text("Dane logowania są przechowywane lokalnie")
            Spacer()
        }
        .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
    }

    private var displayFirstName: String {
        let name = syncManager.librusDisplayName ?? "uczniu"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var selectedCalendarTitle: String? {
        syncManager.calendarChoices.first(where: { $0.id == syncManager.selectedCalendarIdentifier })?.title
    }
}

private struct EventRow: View {
    let event: AgendaEvent
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(accent.opacity(0.1)).frame(width: 43, height: 45)
                VStack(spacing: 1) {
                    Text(event.startDate.formatted(.dateTime.day())).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(event.startDate.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "pl_PL"))).uppercased())
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(3)
                Text(event.dateLabel).font(.caption).foregroundStyle(.secondary)
                Label(event.timeLabel, systemImage: event.isAllDay ? "sun.max" : "clock")
                    .font(.caption2.weight(.medium)).foregroundStyle(accent)
            }
            Spacer(minLength: 0)
            Image(systemName: "calendar").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
        }
        .padding(14)
    }
}


private struct CafeteriaView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var document: PDFDocument?
    @State private var currentMenuURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage = "Jadłospis sprawdzany automatycznie co 7 dni."

    private var menuURLForOpening: URL {
        currentMenuURL ?? CafeteriaMenuService.fallbackPDFURL
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.38, green: 0.30, blue: 0.93))
                        .frame(width: 48, height: 48)
                        .background(Color(red: 0.38, green: 0.30, blue: 0.93).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jadłospis szkolny")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.primary)
                        Text("Stołówka • SP1 Bieruń")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                Text("Aplikacja szuka aktualnego PDF-a na stronie szkoły. Poprzedni poprawny plan zostaje zapisany na telefonie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        Task { await loadMenu(forceSourceCheck: true) }
                    } label: {
                        Label(isLoading ? "Sprawdzanie…" : "Sprawdź teraz", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.38, green: 0.30, blue: 0.93))
                    .disabled(isLoading)

                    Spacer(minLength: 0)

                    Link(destination: menuURLForOpening) {
                        Label("Otwórz PDF", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))

            Divider()

            Group {
                if isLoading && document == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Sprawdzam stronę szkoły i pobieram jadłospis…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    CafeteriaPDFView(document: document)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Aktualny jadłospis stołówki w formacie PDF")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("Nie udało się pobrać jadłospisu")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await loadMenu(forceSourceCheck: true) }
                        } label: {
                            Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.38, green: 0.30, blue: 0.93))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Jadłospis jest gotowy do sprawdzenia")
                            .font(.headline)
                        Button {
                            Task { await loadMenu(forceSourceCheck: true) }
                        } label: {
                            Label("Sprawdź jadłospis", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await loadMenu(forceSourceCheck: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadMenu(forceSourceCheck: false) }
            }
        }
    }

    @MainActor
    private func loadMenu(forceSourceCheck: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await CafeteriaMenuService.refreshIfNeeded(force: forceSourceCheck)
            guard let data = CafeteriaMenuService.cachedPDFData(),
                  let pdf = PDFDocument(data: data) else {
                throw CafeteriaLoadError.invalidPDF
            }

            document = pdf
            currentMenuURL = CafeteriaMenuService.savedPDFURL ?? CafeteriaMenuService.fallbackPDFURL
            if let checkedAt = CafeteriaMenuService.lastCheckedAt {
                statusMessage = "Stronę szkoły sprawdzono: \(checkedAt.formatted(date: .abbreviated, time: .shortened))."
            } else {
                statusMessage = "Pokazuję zapisaną wersję. Ponowna próba znalezienia aktualnego planu nastąpi przy kolejnym otwarciu."
            }
        } catch {
            // Do not replace a valid cached plan with an error screen when the school
            // site is temporarily unavailable. Try the previously used PDF once if this
            // is the first run and no cached document exists.
            if let data = CafeteriaMenuService.cachedPDFData(),
               let pdf = PDFDocument(data: data) {
                document = pdf
                currentMenuURL = CafeteriaMenuService.savedPDFURL ?? CafeteriaMenuService.fallbackPDFURL
                statusMessage = "Nie udało się sprawdzić nowego planu. Wyświetlam ostatnio zapisaną wersję."
            } else {
                do {
                    let fallbackData = try await CafeteriaMenuService.downloadFallbackPDF()
                    guard let pdf = PDFDocument(data: fallbackData) else {
                        throw CafeteriaLoadError.invalidPDF
                    }
                    document = pdf
                    currentMenuURL = CafeteriaMenuService.fallbackPDFURL
                    statusMessage = "Nie udało się znaleźć nowego linku. Wyświetlam poprzedni jadłospis; sprawdź ponownie później."
                } catch {
                    errorMessage = error.localizedDescription
                    statusMessage = "Automatyczne sprawdzanie następuje przy otwarciu aplikacji i może być też uruchomione przez iOS w tle."
                }
            }
        }
    }
}

enum CafeteriaMenuService {
    static let sourcePageURL = URL(string: "https://sp1.bierun.pl/informacje/stolowka")!
    static let fallbackPDFURL = URL(string: "https://sp1.bierun.pl/pliki/JADLOSPIS-2610-3010,82.pdf?view=1")!
    static let weeklyInterval: TimeInterval = 7 * 24 * 60 * 60

    private static let lastCheckedKey = "cafeteriaMenu.lastCheckedAt"
    private static let pdfURLKey = "cafeteriaMenu.pdfURL"
    private static let cacheFileName = "cafeteria-menu-sp1-bierun.pdf"

    static var lastCheckedAt: Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastCheckedKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    static var savedPDFURL: URL? {
        guard let value = UserDefaults.standard.string(forKey: pdfURLKey) else { return nil }
        return URL(string: value)
    }

    static func cachedPDFData() -> Data? {
        guard let url = cacheFileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func refreshIfNeeded(force: Bool = false) async throws -> Bool {
        let hasCache = cachedPDFData() != nil
        let hasURL = savedPDFURL != nil
        let age = lastCheckedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard force || !hasCache || !hasURL || age >= weeklyInterval else {
            return false
        }

        let latestURL = try await discoverLatestPDFURL()
        let data = try await downloadPDF(at: latestURL)
        guard PDFDocument(data: data) != nil else {
            throw CafeteriaLoadError.invalidPDF
        }

        guard let destination = cacheFileURL else {
            throw CafeteriaLoadError.cannotStoreCache
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)

        UserDefaults.standard.set(latestURL.absoluteString, forKey: pdfURLKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckedKey)
        return true
    }

    static func downloadFallbackPDF() async throws -> Data {
        let data = try await downloadPDF(at: fallbackPDFURL)
        guard PDFDocument(data: data) != nil else {
            throw CafeteriaLoadError.invalidPDF
        }
        if let destination = cacheFileURL {
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: destination, options: .atomic)
        }
        // Do not update lastCheckedAt: the official school page should be retried
        // until it can be parsed successfully.
        UserDefaults.standard.set(fallbackPDFURL.absoluteString, forKey: pdfURLKey)
        return data
    }

    private static var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private static func discoverLatestPDFURL() async throws -> URL {
        var request = URLRequest(url: sourcePageURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw CafeteriaLoadError.invalidSourcePage
        }
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw CafeteriaLoadError.invalidSourcePage
        }

        let headingPattern = #"(?is)jad[łl]ospis\s*[-–—]\s*aktualny\s*tydzie[ńn]"#
        guard let headingRegex = try? NSRegularExpression(pattern: headingPattern),
              let headingMatch = headingRegex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
              ) else {
            throw CafeteriaLoadError.currentWeekNotFound
        }

        let sectionStart = headingMatch.range.location + headingMatch.range.length
        let htmlNSString = html as NSString
        let remainingRange = NSRange(location: sectionStart, length: htmlNSString.length - sectionStart)
        let remainingHTML = htmlNSString.substring(with: remainingRange)
        let nextHeadingPattern = #"(?is)<h[1-6]\b"#
        let section: String
        if let nextHeadingRegex = try? NSRegularExpression(pattern: nextHeadingPattern),
           let nextHeading = nextHeadingRegex.firstMatch(
             in: remainingHTML,
             range: NSRange(remainingHTML.startIndex..., in: remainingHTML)
           ) {
            section = (remainingHTML as NSString).substring(to: nextHeading.range.location)
        } else {
            section = remainingHTML
        }

        let anchorPattern = #"(?is)<a\b([^>]*)>(.*?)</a>"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern) else {
            throw CafeteriaLoadError.currentWeekNotFound
        }

        for match in anchorRegex.matches(in: section, range: NSRange(section.startIndex..., in: section)) {
            let attributes = (section as NSString).substring(with: match.range(at: 1))
            let hrefPattern = #"(?is)\bhref\s*=\s*["']([^"']+)["']"#
            guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern),
                  let hrefMatch = hrefRegex.firstMatch(
                    in: attributes,
                    range: NSRange(attributes.startIndex..., in: attributes)
                  ) else { continue }

            var href = (attributes as NSString).substring(with: hrefMatch.range(at: 1))
            href = href.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#038;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate = URL(string: href, relativeTo: sourcePageURL)?.absoluteURL,
                  candidate.scheme == "https",
                  candidate.host?.lowercased() == "sp1.bierun.pl",
                  candidate.pathExtension.lowercased() == "pdf" else { continue }
            return candidate
        }

        throw CafeteriaLoadError.currentWeekNotFound
    }

    private static func downloadPDF(at url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw CafeteriaLoadError.invalidResponse
        }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw CafeteriaLoadError.invalidPDF
        }
        return data
    }
}

private enum CafeteriaLoadError: LocalizedError {
    case invalidSourcePage
    case currentWeekNotFound
    case invalidResponse
    case invalidPDF
    case cannotStoreCache

    var errorDescription: String? {
        switch self {
        case .invalidSourcePage:
            return "Nie udało się odczytać strony stołówki. Sprawdź połączenie i spróbuj ponownie."
        case .currentWeekNotFound:
            return "Nie znaleziono linku do aktualnego jadłospisu na stronie szkoły."
        case .invalidResponse:
            return "Strona szkoły nie zwróciła poprawnej odpowiedzi. Spróbuj ponownie."
        case .invalidPDF:
            return "Pobrany plik nie jest poprawnym dokumentem PDF."
        case .cannotStoreCache:
            return "Nie udało się zapisać jadłospisu na telefonie."
        }
    }
}

private struct CafeteriaPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = UIColor.systemGroupedBackground
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
