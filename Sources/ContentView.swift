import SwiftUI

struct ContentView: View {
    @StateObject private var syncManager = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var login = KeychainStore.read(key: "librusLogin") ?? ""
    @State private var password = KeychainStore.read(key: "librusPassword") ?? ""
    @State private var showDisconnectConfirmation = false

    private let ink = Color(red: 0.13, green: 0.16, blue: 0.27)
    private let violet = Color(red: 0.38, green: 0.30, blue: 0.93)
    private let lilac = Color(red: 0.63, green: 0.48, blue: 0.98)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    heroCard
                    integrationsSection
                    syncControl
                    upcomingSection
                    backgroundNote
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        }
        .tint(violet)
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
                .background(LinearGradient(colors: [ink, Color(red: 0.22, green: 0.27, blue: 0.43)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .buttonStyle(.plain).disabled(syncManager.isSyncing || !syncManager.isLibrusConnected)

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
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .lastTextBaseline) {
                sectionHeading("Najbliższe wydarzenia", subtitle: "Z terminarza Librus Synergia")
                Spacer()
                Text("\(syncManager.recentEvents.count)").font(.caption.weight(.bold)).foregroundStyle(violet)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(violet.opacity(0.1), in: Capsule())
            }
            if syncManager.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 27)).foregroundStyle(violet)
                    Text("Na razie pusto").font(.headline).foregroundStyle(ink)
                    Text("Po połączeniu Librusa wydarzenia z terminarza pojawią się tutaj i będą synchronizowane z wybranym kalendarzem Apple.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(syncManager.recentEvents.prefix(12).enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, accent: index % 3 == 0 ? violet : Color.blue)
                        if index < min(syncManager.recentEvents.count, 12) - 1 { Divider().padding(.leading, 68) }
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
