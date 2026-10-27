import Foundation

enum LibrusClientError: LocalizedError {
    case invalidLogin, loginRejected, captchaRequired, sessionExpired, serverResponse, missingRedirect, missingSessionCookie, tooManyRedirects, network

    var errorDescription: String? {
        switch self {
        case .invalidLogin: return "Podaj login i hasło do Librus Synergia."
        case .loginRejected: return "Librus nie zaakceptował logowania. Sprawdź login i hasło."
        case .captchaRequired: return "Librus wymaga dodatkowego potwierdzenia logowania. Zaloguj się w oficjalnej aplikacji lub przeglądarce i spróbuj ponownie."
        case .sessionExpired: return "Sesja Librusa wygasła. Spróbuję zalogować konto ponownie."
        case .serverResponse: return "Librus zwrócił nieoczekiwaną odpowiedź. Spróbuj później."
        case .missingRedirect: return "Nie udało się rozpocząć logowania Librus. Spróbuj ponownie później."
        case .missingSessionCookie: return "Logowanie nie zakończyło się poprawnie. Spróbuj ponownie."
        case .tooManyRedirects: return "Logowanie Librus przekroczyło limit przekierowań."
        case .network: return "Nie udało się połączyć z Librusem. Sprawdź internet."
        }
    }
}

struct LibrusSnapshot {
    let displayName: String
    let events: [AgendaEvent]
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class LibrusClient {
    static let shared = LibrusClient()
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    private let portalLogin = URL(string: "https://synergia.librus.pl/loguj/portalRodzina")!
    private let authorizationURL = URL(string: "https://api.librus.pl/OAuth/Authorization?client_id=46")!
    private let authorizationScopedURL = URL(string: "https://api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata")!
    private let gateway = "https://synergia.librus.pl/gateway/api/2.0"

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    func connect(login: String, password: String) async throws -> LibrusSnapshot {
        guard !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw LibrusClientError.invalidLogin
        }
        try await performLogin(login: login, password: password)
        return try await loadSnapshot()
    }

    func synchronize(login: String, password: String) async throws -> LibrusSnapshot {
        do {
            return try await loadSnapshot()
        } catch LibrusClientError.sessionExpired {
            try await performLogin(login: login, password: password)
            return try await loadSnapshot()
        }
    }

    func clearSession() {
        for cookie in (HTTPCookieStorage.shared.cookies ?? []) where cookie.domain.contains("librus.pl") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func performLogin(login: String, password: String) async throws {
        var request = URLRequest(url: portalLogin)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (_, firstResponse) = try await send(request)

        guard let firstLocation = firstResponse.value(forHTTPHeaderField: "Location"),
              let auth = URL(string: firstLocation, relativeTo: firstResponse.url)?.absoluteURL else {
            throw LibrusClientError.missingRedirect
        }

        var authRequest = URLRequest(url: auth)
        authRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        _ = try await send(authRequest)

        var form = URLRequest(url: authorizationURL)
        form.httpMethod = "POST"
        form.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        form.setValue("*/*", forHTTPHeaderField: "Accept")
        form.setValue("en-US,en;q=0.9,pl;q=0.8", forHTTPHeaderField: "Accept-Language")
        form.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        form.setValue("no-cache", forHTTPHeaderField: "Pragma")
        form.setValue("https://api.librus.pl", forHTTPHeaderField: "Origin")
        form.setValue(authorizationURL.absoluteString, forHTTPHeaderField: "Referer")
        form.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        form.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        form.httpBody = encodeForm([("action", "login"), ("login", login), ("pass", password)]).data(using: .utf8)

        let (data, response) = try await send(form)
        if (400...499).contains(response.statusCode) { throw LibrusClientError.loginRejected }
        let responseText = String(decoding: data, as: UTF8.self)
        try checkCaptcha(responseText)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let goTo = json["goTo"] as? String, !goTo.isEmpty,
              var nextURL = URL(string: goTo, relativeTo: authorizationScopedURL)?.absoluteURL else {
            throw LibrusClientError.loginRejected
        }

        var complete = false
        for _ in 0..<10 {
            var redirectRequest = URLRequest(url: nextURL)
            redirectRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (body, redirectResponse) = try await send(redirectRequest)
            try checkCaptcha(String(decoding: body, as: UTF8.self))
            guard let location = redirectResponse.value(forHTTPHeaderField: "Location"),
                  let resolved = URL(string: location, relativeTo: redirectResponse.url)?.absoluteURL else {
                complete = true
                break
            }
            nextURL = resolved
        }
        guard complete else { throw LibrusClientError.tooManyRedirects }

        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://synergia.librus.pl/")!) ?? []
        guard cookies.contains(where: { $0.name == "oauth_token" }) else {
            throw LibrusClientError.missingSessionCookie
        }
    }

    private func loadSnapshot() async throws -> LibrusSnapshot {
        let me = try await getJSON("Me")
        let agenda = try await getJSON("HomeWorks")
        let categoryPayload = (try? await getJSON("HomeWorks/Categories")) ?? [:]
        let subjectPayload = (try? await getJSON("Subjects")) ?? [:]
        let categories = nameMap(categoryPayload, key: "Categories")
        let subjects = nameMap(subjectPayload, key: "Subjects")
        let entries = agenda["HomeWorks"] as? [[String: Any]] ?? []
        let events = entries.compactMap { mapEvent($0, categories: categories, subjects: subjects) }
            .sorted { $0.startDate < $1.startDate }

        let root = (me["Me"] as? [String: Any]) ?? me
        let user = (root["User"] as? [String: Any]) ?? [:]
        let account = (root["Account"] as? [String: Any]) ?? [:]
        let first = text(user["FirstName"]) ?? text(user["Name"]) ?? ""
        let last = text(user["LastName"]) ?? ""
        let joined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return LibrusSnapshot(displayName: joined.isEmpty ? (text(account["Login"]) ?? "Konto Librus połączone") : joined, events: events)
    }

    private func getJSON(_ endpoint: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(gateway)/\(endpoint)") else { throw LibrusClientError.serverResponse }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://synergia.librus.pl/", forHTTPHeaderField: "Referer")
        let (data, response) = try await send(request)
        if response.statusCode == 401 || response.statusCode == 403 { throw LibrusClientError.sessionExpired }
        guard (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibrusClientError.serverResponse
        }
        return json
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LibrusClientError.serverResponse }
            return (data, http)
        } catch let error as LibrusClientError {
            throw error
        } catch {
            throw LibrusClientError.network
        }
    }

    private func checkCaptcha(_ value: String) throws {
        let text = value.lowercased()
        if text.contains("captcha") || text.contains("g-recaptcha") || text.contains("hcaptcha") {
            throw LibrusClientError.captchaRequired
        }
    }

    private func encodeForm(_ fields: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    private func nameMap(_ payload: [String: Any], key: String) -> [String: String] {
        var result: [String: String] = [:]
        for row in (payload[key] as? [[String: Any]] ?? []) {
            guard let id = text(row["Id"]), let name = text(row["Name"]) ?? text(row["ShortName"]) else { continue }
            result[id] = name
        }
        return result
    }

    private func mapEvent(_ row: [String: Any], categories: [String: String], subjects: [String: String]) -> AgendaEvent? {
        guard let id = text(row["Id"]), let rawDate = text(row["Date"]), let day = parseDate(rawDate) else { return nil }

        let category = nestedID(row["Category"]).flatMap { categories[$0] }
        let subject = nestedID(row["Subject"]).flatMap { subjects[$0] }
        let content = (text(row["Content"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var titleParts: [String] = []
        if !content.isEmpty { titleParts.append(content) }
        if let subject, !content.localizedCaseInsensitiveContains(subject) { titleParts.append(subject) }
        if titleParts.isEmpty, let category { titleParts.append(category) }
        let title = titleParts.isEmpty ? "Wydarzenie z Librusa" : titleParts.joined(separator: " • ")

        let timeFrom = text(row["TimeFrom"])
        let start = timeFrom.flatMap { combine(day: day, time: $0) }
        let explicitDateTime = rawDate.contains("T") || rawDate.contains(":")
        let eventStart = start ?? (explicitDateTime ? day : midnight(day))
        let allDay = start == nil && !explicitDateTime
        let end = eventStart.addingTimeInterval(allDay ? 86_400 : 3_600)
        let notes = [category.map { "Kategoria: \($0)" }, subject.map { "Przedmiot: \($0)" }, content.isEmpty ? nil : content]
            .compactMap { $0 }.joined(separator: "\n")

        return AgendaEvent(uid: "librus-homework-\(id)", title: title, startDate: eventStart, endDate: end, notes: notes, isAllDay: allDay)
    }

    private func nestedID(_ value: Any?) -> String? {
        guard let row = value as? [String: Any] else { return nil }
        return text(row["Id"])
    }

    private func text(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private func midnight(_ day: Date) -> Date {
        var components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        components.timeZone = TimeZone(identifier: "Europe/Warsaw")
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar(identifier: .gregorian).date(from: components) ?? day
    }

    private func combine(day: Date, time: String) -> Date? {
        let pattern = #"^(\d{1,2}):(\d{2})(?::(\d{2}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: time, range: NSRange(time.startIndex..., in: time)),
              let hr = Range(match.range(at: 1), in: time), let min = Range(match.range(at: 2), in: time) else {
            return parseDate(time)
        }
        var components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        components.timeZone = TimeZone(identifier: "Europe/Warsaw")
        components.hour = Int(time[hr]) ?? 0
        components.minute = Int(time[min]) ?? 0
        components.second = 0
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
