import Foundation

struct AgendaEvent: Identifiable, Codable, Equatable {
    let uid: String
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String
    var isAllDay: Bool

    var id: String { uid }

    /// Upcoming timed events start in the future. All-day events scheduled for today
    /// remain visible until the local day ends.
    var isUpcoming: Bool {
        let now = Date()
        if isAllDay {
            return startDate >= Calendar.current.startOfDay(for: now)
        }
        return endDate >= now
    }

    /// Best-effort classification based on the text Librus exposes for an entry.
    var isAssessment: Bool {
        let text = "\(title) \(notes)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .lowercased()
        let markers = ["sprawdzian", "kartkowka", "praca klasowa", "test", "egzamin", "spr."]
        return markers.contains { text.contains($0) }
    }

    var countdownLabel: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
        switch days {
        case ..<0: return "Trwa lub minęło"
        case 0: return "Dzisiaj"
        case 1: return "Jutro"
        default: return "Za \(days) dni"
        }
    }

    init(uid: String, title: String, startDate: Date, endDate: Date, notes: String, isAllDay: Bool = false) {
        self.uid = uid
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.isAllDay = isAllDay
    }

    private enum CodingKeys: String, CodingKey { case uid, title, startDate, endDate, notes, isAllDay }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uid = try values.decode(String.self, forKey: .uid)
        title = try values.decode(String.self, forKey: .title)
        startDate = try values.decode(Date.self, forKey: .startDate)
        endDate = try values.decode(Date.self, forKey: .endDate)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isAllDay = try values.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(uid, forKey: .uid)
        try values.encode(title, forKey: .title)
        try values.encode(startDate, forKey: .startDate)
        try values.encode(endDate, forKey: .endDate)
        try values.encode(notes, forKey: .notes)
        try values.encode(isAllDay, forKey: .isAllDay)
    }

    var fingerprint: String {
        [title, String(startDate.timeIntervalSince1970), String(endDate.timeIntervalSince1970), notes, String(isAllDay)]
            .joined(separator: "|")
    }

    var dateLabel: String {
        startDate.formatted(.dateTime.locale(Locale(identifier: "pl_PL")).weekday(.wide).day().month(.wide))
    }

    var timeLabel: String {
        if isAllDay { return "Cały dzień" }
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return "\(startDate.formatted(date: .omitted, time: .shortened))–\(endDate.formatted(date: .omitted, time: .shortened))"
        }
        return startDate.formatted(date: .numeric, time: .shortened)
    }
}

enum SyncError: LocalizedError {
    case invalidURL
    case insecureURL
    case badHTTPResponse
    case emptyCalendar
    case calendarPermissionDenied
    case noCalendarSource

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Wpisz poprawny adres kalendarza."
        case .insecureURL: return "Dla bezpieczeństwa obsługiwane są tylko adresy HTTPS."
        case .badHTTPResponse: return "Źródło nie zwróciło poprawnej odpowiedzi. Sprawdź adres kalendarza."
        case .emptyCalendar: return "Pod tym adresem nie znaleziono kalendarza iCalendar (.ics)."
        case .calendarPermissionDenied: return "Brak dostępu do Kalendarza Apple. Zezwól na niego w Ustawieniach iPhone’a."
        case .noCalendarSource: return "Nie znaleziono źródła, w którym można utworzyć kalendarz."
        }
    }
}


struct LessonPeriod: Codable, Identifiable, Equatable {
    let id: String
    let number: Int
    let subject: String
    let teacherAndRoom: String
    let startTime: String
    let endTime: String
    var isSubstitution: Bool

    private enum CodingKeys: String, CodingKey {
        case id, number, subject, teacherAndRoom, startTime, endTime, isSubstitution
    }

    init(
        id: String,
        number: Int,
        subject: String,
        teacherAndRoom: String,
        startTime: String,
        endTime: String,
        isSubstitution: Bool = false
    ) {
        self.id = id
        self.number = number
        self.subject = subject
        self.teacherAndRoom = teacherAndRoom
        self.startTime = startTime
        self.endTime = endTime
        self.isSubstitution = isSubstitution
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        number = try values.decode(Int.self, forKey: .number)
        subject = try values.decode(String.self, forKey: .subject)
        teacherAndRoom = try values.decode(String.self, forKey: .teacherAndRoom)
        startTime = try values.decode(String.self, forKey: .startTime)
        endTime = try values.decode(String.self, forKey: .endTime)
        isSubstitution = try values.decodeIfPresent(Bool.self, forKey: .isSubstitution) ?? false
    }
}

struct TimetableDay: Codable, Identifiable, Equatable {
    let id: String
    let date: Date
    let lessons: [LessonPeriod]
}

enum TimetableLoadError: LocalizedError {
    case accountNotConnected
    case noPublishedPlan
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .accountNotConnected:
            return "Najpierw połącz konto Librus w zakładce Start."
        case .noPublishedPlan:
            return "Librus nie udostępnia planu lekcji dla tego tygodnia. Szkoła może jeszcze nie opublikować planu na koncie ucznia."
        case .invalidResponse:
            return "Nie udało się odczytać planu lekcji z Librusa. Spróbuj ponownie."
        }
    }
}
