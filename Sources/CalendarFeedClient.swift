import Foundation

struct CalendarFeedClient {
    func fetchEvents(from rawURL: String) async throws -> [AgendaEvent] {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              url.host != nil else {
            throw SyncError.invalidURL
        }
        guard scheme == "https" else {
            throw SyncError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("text/calendar, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw SyncError.badHTTPResponse
        }
        guard data.count <= 5 * 1024 * 1024 else {
            throw SyncError.badHTTPResponse
        }

        let text = String(decoding: data, as: UTF8.self)
        guard text.localizedCaseInsensitiveContains("BEGIN:VCALENDAR") else {
            throw SyncError.emptyCalendar
        }
        return ICalendarParser.parse(text)
    }
}