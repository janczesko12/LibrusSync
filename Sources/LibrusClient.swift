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
        // Usuń stare ciasteczka przed nowym logowaniem. Wygasły oauth_token może
        // pozostać w magazynie i powodować błędy mimo poprawnego ponownego logowania.
        clearSession()

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

        // Przekierowania są obsługiwane ręcznie. Wygasła sesja Librusa często
        // zwraca 302 do strony HTML logowania, co wcześniej dawało tylko serverResponse
        // i uniemożliwiało uruchomienie automatycznego ponownego logowania.
        if response.statusCode == 401 || response.statusCode == 403 ||
            (300..<400).contains(response.statusCode) {
            throw LibrusClientError.sessionExpired
        }

        guard (200..<300).contains(response.statusCode) else {
            throw LibrusClientError.serverResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("text/html") || body.contains("<html") ||
                body.contains("loguj/portal") || body.contains("oauth/authorization") {
                throw LibrusClientError.sessionExpired
            }
            throw LibrusClientError.serverResponse
        }

        // Czasem API zwraca błąd autoryzacji jako JSON przy statusie HTTP 200.
        if let code = json["status"] as? Int, [401, 403].contains(code) {
            throw LibrusClientError.sessionExpired
        }
        if endpoint == "HomeWorks" && json["HomeWorks"] == nil {
            throw LibrusClientError.sessionExpired
        }
        if endpoint == "Me" && json["Me"] == nil &&
            json["User"] == nil && json["Account"] == nil {
            throw LibrusClientError.sessionExpired
        }
        return json
    }


    /// Fetch the published weekly timetable from Librus Synergia.
    /// Librus exposes this view as an authenticated HTML page rather than a stable public JSON API.
    func fetchTimetable(weekStarting date: Date) async throws -> [TimetableDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: date)),
              let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
            throw TimetableLoadError.invalidResponse
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekValue = "\(dateFormatter.string(from: monday))_\(dateFormatter.string(from: sunday))"

        guard let url = URL(string: "https://synergia.librus.pl/przegladaj_plan_lekcji") else {
            throw TimetableLoadError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("https://synergia.librus.pl/", forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = encodeForm([("tydzien", weekValue)]).data(using: .utf8)

        let (data, response) = try await send(request)
        if response.statusCode == 401 || response.statusCode == 403 || (300..<400).contains(response.statusCode) {
            throw LibrusClientError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw TimetableLoadError.invalidResponse
        }
        return try parseTimetableHTML(html, monday: monday, calendar: calendar)
    }

    private func parseTimetableHTML(_ html: String, monday: Date, calendar: Calendar) throws -> [TimetableDay] {
        func matches(_ pattern: String, in source: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { return [] }
            let range = NSRange(source.startIndex..., in: source)
            return regex.matches(in: source, range: range).map { result in
                (0..<result.numberOfRanges).map { index in
                    guard let range = Range(result.range(at: index), in: source) else { return "" }
                    return String(source[range])
                }
            }
        }

        func plainText(_ source: String) -> String {
            var value = source
                .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: " • ", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)</(div|p|li)>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            let entities: [(String, String)] = [
                ("&nbsp;", " "), ("&#160;", " "), ("&#xa0;", " "),
                ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"),
                ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")
            ]
            for (entity, replacement) in entities {
                value = value.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
            }
            value = value.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func parseDate(_ value: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value)
        }

        let tablePattern = #"<table\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bplan-lekcji\b[^"']*["'])[^>]*>(.*?)</table>"#
        guard let table = matches(tablePattern, in: html).first, table.count > 1 else {
            throw TimetableLoadError.noPublishedPlan
        }

        let rowPattern = #"<tr\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bline1\b[^"']*["'])[^>]*>(.*?)</tr>"#
        let rows = matches(rowPattern, in: table[1])
        guard !rows.isEmpty else { throw TimetableLoadError.noPublishedPlan }

        var lessonsByDay = Array(repeating: [LessonPeriod](), count: 5)
        let cellPattern = #"<td\b(?=[^>]*\bid\s*=\s*["']timetableEntryBox["'])(?=[^>]*\bclass\s*=\s*["']line1["'])[^>]*>(.*?)</td>"#
        let centerCellPattern = #"<td\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bcenter\b[^"']*["'])[^>]*>(.*?)</td>"#
        let dataAttributePattern = #"\bdata-[A-Za-z0-9_-]+\s*=\s*["']([^"']*)["']"#
        let textDivPattern = #"<div\b(?=[^>]*\bclass\s*=\s*["'][^"']*\btext\b[^"']*["'])[^>]*>(.*?)</div>"#
        let boldPattern = #"<b\b[^>]*>(.*?)</b>"#
        let boldRemovalPattern = #"<b\b[^>]*>.*?</b>"#

        for (rowIndex, rowMatch) in rows.enumerated() {
            let rowHTML = rowMatch.count > 1 ? rowMatch[1] : ""
            let numberHTML = matches(centerCellPattern, in: rowHTML).first
            let periodNumber = numberHTML.flatMap { $0.count > 1 ? Int(plainText($0[1])) : nil } ?? (rowIndex + 1)
            let cells = matches(cellPattern, in: rowHTML)

            for (dayIndex, cell) in cells.prefix(5).enumerated() {
                guard cell.count > 1 else { continue }
                let cellTag = cell[0]
                let cellHTML = cell[1]
                let dataValues = matches(dataAttributePattern, in: cellTag).compactMap { $0.count > 1 ? $0[1] : nil }
                func attribute(_ name: String) -> String? {
                    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']*)["']"#
                    return matches(pattern, in: cellTag).first.flatMap { $0.count > 1 ? $0[1] : nil }
                }

                let dateText = attribute("data-date") ?? dataValues.first ?? ""
                let startTime = attribute("data-from") ?? dataValues.dropFirst().first ?? ""
                let endTime = attribute("data-to") ?? dataValues.dropFirst(2).first ?? ""
                let lessonDate = parseDate(dateText) ?? calendar.date(byAdding: .day, value: dayIndex, to: monday) ?? monday

                let textDivs = matches(textDivPattern, in: cellHTML)
                var subjects: [String] = []
                var teacherAndRoom: [String] = []
                for div in textDivs where div.count > 1 {
                    let segment = div[1]
                    let names = matches(boldPattern, in: segment).compactMap { $0.count > 1 ? plainText($0[1]) : nil }.filter { !$0.isEmpty }
                    subjects.append(contentsOf: names)
                    let withoutSubject = segment.replacingOccurrences(
                        of: boldRemovalPattern,
                        with: " ",
                        options: [.regularExpression, .caseInsensitive]
                    )
                    let details = plainText(withoutSubject)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " -•\t\n\r"))
                    if !details.isEmpty { teacherAndRoom.append(details) }
                }

                let subject = subjects.joined(separator: " / ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !subject.isEmpty else { continue }
                let detail = teacherAndRoom.joined(separator: " / ")

                // Librus can mark substitutions in visible text, title/alt attributes
                // or CSS classes. Normalize Polish diacritics before checking the marker.
                let substitutionSource = "\(cellTag) \(cellHTML)"
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
                    .lowercased()
                let isSubstitution =
                    substitutionSource.contains("zastepstwo") ||
                    substitutionSource.contains("zastepca") ||
                    substitutionSource.contains("substitution") ||
                    substitutionSource.range(of: #"\\bzast\\.?\\b"#, options: .regularExpression) != nil

                let dateKey = Int(lessonDate.timeIntervalSince1970)
                let lessonID = "\(dateKey)-\(periodNumber)-\(startTime)"
                lessonsByDay[dayIndex].append(
                    LessonPeriod(
                        id: lessonID,
                        number: periodNumber,
                        subject: subject,
                        teacherAndRoom: detail,
                        startTime: startTime,
                        endTime: endTime,
                        isSubstitution: isSubstitution
                    )
                )
            }
        }

        guard lessonsByDay.contains(where: { !$0.isEmpty }) else {
            throw TimetableLoadError.noPublishedPlan
        }

        return (0..<5).compactMap { index in
            guard let dayDate = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            let dayID = String(Int(dayDate.timeIntervalSince1970))
            let orderedLessons = lessonsByDay[index].sorted { lhs, rhs in
                if lhs.number != rhs.number { return lhs.number < rhs.number }
                return lhs.startTime < rhs.startTime
            }
            return TimetableDay(id: dayID, date: dayDate, lessons: orderedLessons)
        }
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
