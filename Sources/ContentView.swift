import SwiftUI

struct ContentView: View {
    @StateObject private var syncManager = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedURL = KeychainStore.read(key: "calendarFeedURL") ?? ""
    @State private var showSavedMessage = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    sourceCard
                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    statusCard
                    eventsSection
                    backgroundInfo
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LibrusSync")
                        .font(.headline.weight(.bold))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    BackgroundRefreshScheduler.shared.scheduleNext()
                }
            }
            .alert("Zapisano", isPresented: $showSavedMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Adres źródła zapisano bezpiecznie w pęku kluczy iOS.")
            }
        }
        .tint(Color.indigo)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.indigo.gradient)
                        .frame(width: 60, height: 60)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Twój terminarz pod kontrolą")
                        .font(.title3.bold())
                    Text("Synchronizacja w tle, bez serwera")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("LibrusSync porównuje wydarzenia, aktualizuje Kalendarz Apple i powiadamia o wykrytych zmianach.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Źródło terminarza", systemImage: "link")
                .font(.headline)

            Text("Wklej prywatny adres kalendarza HTTPS w formacie iCalendar (.ics). To nie jest hasło do Librusa.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("https://…/kalendarz.ics", text: $feedURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Adres kalendarza ICS")

            HStack(spacing: 10) {
                Button {
                    let cleaned = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.isEmpty {
                        KeychainStore.delete(key: "calendarFeedURL")
                        saveError = nil
                        showSavedMessage = true
                    } else if KeychainStore.save(cleaned, key: "calendarFeedURL") {
                        saveError = nil
                        BackgroundRefreshScheduler.shared.scheduleNext()
                        showSavedMessage = true
                    } else {
                        saveError = "Nie udało się zapisać adresu w pęku kluczy iOS."
                    }
                } label: {
                    Label("Zapisz źródło", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await syncManager.syncNow(feedURL: feedURL) }
                } label: {
                    if syncManager.isSyncing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Sprawdź teraz", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncManager.isSyncing || feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Status", systemImage: "waveform.path")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(syncManager.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
            }
            Text(syncManager.status)
                .font(.title3.weight(.semibold))
            if let lastSync = syncManager.lastSync {
                Label("Ostatnio: \(lastSync.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = syncManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ostatnio pobrane wydarzenia")
                    .font(.headline)
                Spacer()
                Text("\(syncManager.recentEvents.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if syncManager.recentEvents.isEmpty {
                ContentUnavailableView(
                    "Brak wydarzeń",
                    systemImage: "calendar",
                    description: Text("Zapisz adres kalendarza i uruchom pierwszą synchronizację.")
                )
                .frame(minHeight: 145)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(syncManager.recentEvents) { event in
                        EventRow(event: event)
                        if event.id != syncManager.recentEvents.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var backgroundInfo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text("Oszczędzanie baterii")
                    .font(.subheadline.weight(.semibold))
                Text("Aplikacja nie działa w pętli. iOS może wybudzić ją w tle, ale sam ustala termin i nie gwarantuje konkretnej częstotliwości.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EventRow: View {
    let event: AgendaEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.indigo)
                .frame(width: 4, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(event.dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.timeLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
            }
            Spacer(minLength: 0)
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}