import SwiftUI
import PhotosUI
import Vision
import ImageIO

private struct AIStudyRequest: Encodable {
    let subject: String
    let topic: String
    let assessmentDate: String
    let materials: String
}

private struct AIStudyResponse: Decodable {
    let plan: String
}

@MainActor
private final class AIStudyViewModel: ObservableObject {
    @Published var subject = "Geografia"
    @Published var topic = ""
    @Published var materials = ""
    @Published var selectedDate = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
    @Published var plan = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedPhoto: PhotosPickerItem?

    func generate() async {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTopic.isEmpty else {
            error = "Wpisz temat kartkówki lub sprawdzianu."
            return
        }
        guard let token = KeychainStore.read(key: "widgetRemoteWriteToken"), !token.isEmpty else {
            error = "Brak danych autoryzacyjnych. Otwórz Ustawienia i wykonaj synchronizację LibrusSync."
            return
        }

        isLoading = true
        error = nil
        plan = ""
        defer { isLoading = false }

        do {
            var request = URLRequest(url: URL(string: "https://librussync-widget-api.vercel.app/api/ai-study")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(AIStudyRequest(
                subject: subject,
                topic: cleanTopic,
                assessmentDate: ISO8601DateFormatter().string(from: selectedDate),
                materials: String(materials.prefix(18000))
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "AIStudy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowa odpowiedź serwera."])
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "Serwer AI zwrócił błąd (\(http.statusCode))."
                throw NSError(domain: "AIStudy", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            let decoded = try JSONDecoder().decode(AIStudyResponse.self, from: data)
            plan = decoded.plan
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recognizeText(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                error = "Nie udało się odczytać zdjęcia."
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pl-PL", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else {
                error = "Nie rozpoznano tekstu. Spróbuj zrobić wyraźniejsze zdjęcie."
                return
            }
            materials += (materials.isEmpty ? "" : "\n\n") + text
            error = nil
        } catch {
            self.error = "Nie udało się rozpoznać tekstu ze zdjęcia: \(error.localizedDescription)"
        }
    }

    func useAssessment(_ event: AgendaEvent) {
        let text = event.title
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
        let parts = normalized.components(separatedBy: " - ")
        if parts.count > 1 {
            subject = parts[0].capitalized
            topic = parts.dropFirst().joined(separator: " - ")
        } else {
            topic = text
        }
        selectedDate = event.startDate
        if !event.notes.isEmpty { materials = event.notes }
    }
}

struct AIStudyView: View {
    @StateObject private var model = AIStudyViewModel()
    @StateObject private var syncManager = SyncManager.shared
    @State private var selectedEventID: String?

    private let subjects = ["Język polski", "Matematyka", "Geografia", "Historia", "Biologia", "Przyroda", "Chemia", "Fizyka", "Język angielski", "Informatyka", "Inny"]

    private var assessments: [AgendaEvent] {
        syncManager.recentEvents.filter { $0.isAssessment }.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !assessments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Sprawdziany z Librusa", systemImage: "calendar.badge.exclamationmark")
                                .font(.headline)
                            ForEach(assessments) { event in
                                Button {
                                    selectedEventID = event.uid
                                    model.useAssessment(event)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(event.title).font(.subheadline.weight(.semibold))
                                            Text("\(event.dateLabel) • \(event.countdownLabel)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedEventID == event.uid {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Przygotuj naukę").font(.headline)
                        Picker("Przedmiot", selection: $model.subject) {
                            ForEach(subjects, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        TextField("Temat kartkówki lub sprawdzianu", text: $model.topic, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        DatePicker("Data sprawdzianu", selection: $model.selectedDate, in: Date()..., displayedComponents: .date)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Materiały i zakres (opcjonalnie)").font(.subheadline.weight(.semibold))
                            TextEditor(text: $model.materials)
                                .frame(minHeight: 110)
                                .padding(5)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                            PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
                                Label("Dodaj zdjęcie podręcznika lub zeszytu", systemImage: "photo")
                                    .font(.subheadline.weight(.medium))
                            }
                            .onChange(of: model.selectedPhoto) { _, item in
                                guard let item else { return }
                                Task { await model.recognizeText(from: item) }
                            }
                            Text("Tekst ze zdjęcia jest rozpoznawany na iPhonie. Zdjęcie nie jest wysyłane na serwer.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await model.generate() }
                        } label: {
                            HStack {
                                if model.isLoading { ProgressView().tint(.white) }
                                Image(systemName: "sparkles")
                                Text(model.isLoading ? "Tworzę plan nauki…" : "Wygeneruj plan nauki")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading || model.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(15)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if !model.plan.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Twój plan nauki", systemImage: "book.closed.fill")
                                .font(.headline)
                            Text(LocalizedStringKey(model.plan))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(15)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(18)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("AI Nauczyciel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.purple)
                Text("Twój osobisty nauczyciel").font(.title2.bold())
            }
            Text("Wybierz sprawdzian z Librusa lub wpisz temat. AI przygotuje plan, lekcje, quizy i próbny test.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.purple.opacity(0.13), Color.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }
}
