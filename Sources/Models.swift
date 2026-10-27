import Foundation

struct AgendaEvent: Identifiable, Codable, Equatable {
    let uid: String
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String

    var id: String { uid }

    var fingerprint: String {
        [
            title,
            String(startDate.timeIntervalSince1970),
            String(endDate.timeIntervalSince1970),
            notes
        ].joined(separator: "|")
    }

    var dateLabel: String {
        startDate.formatted(
            .dateTime.locale(Locale(identifier: "pl_PL"))
                .weekday(.wide).day().month(.wide)
        )
    }

    var timeLabel: String {
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
        case .invalidURL:
            return "Wpisz poprawny adres kalendarza."
        case .insecureURL:
            return "Dla bezpieczeństwa obsługiwane są tylko adresy HTTPS."
        case .badHTTPResponse:
            return "Źródło nie zwróciło poprawnej odpowiedzi. Sprawdź adres kalendarza."
        case .emptyCalendar:
            return "Pod tym adresem nie znaleziono kalendarza iCalendar (.ics)."
        case .calendarPermissionDenied:
            return "Brak dostępu do Kalendarza Apple. Zezwól na niego w Ustawieniach iPhone’a."
        case .noCalendarSource:
            return "Nie znaleziono źródła, w którym można utworzyć kalendarz."
        }
    }
}