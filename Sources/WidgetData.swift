import Foundation
import Security
import WidgetKit

struct WidgetRemoteCredentials {
    let id: String
    let readToken: String
    let writeToken: String
    var shareCode: String { "\(id)|\(readToken)" }
}

private struct WidgetPublishPayload: Encodable {
    let id: String
    let readToken: String
    let events: [AgendaEvent]
}
private struct WidgetRemoteEventsResponse: Decodable { let events: [AgendaEvent] }
private struct WidgetPublishResponse: Decodable {
    let ok: Bool?
    let count: Int?
    let error: String?
}

enum WidgetRemoteStore {
    static let apiURL = URL(string: "https://librussync-widget-api.vercel.app/api/events")!

    static func makeCredentials() -> WidgetRemoteCredentials? {
        func randomToken() -> String? {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = bytes.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }
            guard status == errSecSuccess else { return nil }
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        guard let readToken = randomToken(), let writeToken = randomToken() else { return nil }
        return WidgetRemoteCredentials(id: UUID().uuidString.lowercased(), readToken: readToken, writeToken: writeToken)
    }

    static func publish(events: [AgendaEvent], id: String, readToken: String, writeToken: String) async -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(writeToken)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(
                WidgetPublishPayload(id: id, readToken: readToken, events: Array(events.prefix(30)))
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Widżet: serwer zwrócił nieprawidłową odpowiedź."
            }
            guard (200..<300).contains(http.statusCode) else {
                let serverError = (try? JSONDecoder().decode(WidgetPublishResponse.self, from: data).error) ?? "HTTP \(http.statusCode)"
                return "Widżet: nie udało się wysłać danych (\(serverError))."
            }
            WidgetCenter.shared.reloadAllTimelines()
            let result = try? JSONDecoder().decode(WidgetPublishResponse.self, from: data)
            return "Widżet: wysłano \(result?.count ?? events.count) wydarzeń na bezpieczny serwer. Wklej kod widżetu w jego ustawieniach."
        } catch {
            return "Widżet: brak połączenia z serwerem. Sprawdź internet i ponów synchronizację."
        }
    }

    static func loadUpcomingEvents(accessCode: String) async -> [AgendaEvent] {
        let parts = accessCode.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count == 2, let id = UUID(uuidString: parts[0]), parts[1].count >= 40 else { return [] }
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: id.uuidString.lowercased())]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(parts[1])", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(WidgetRemoteEventsResponse.self, from: data)
            return Array(decoded.events.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate }.prefix(30))
        } catch {
            return []
        }
    }
}
