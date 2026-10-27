import Foundation

enum ICalendarParser {
    static func parse(_ text: String) -> [AgendaEvent] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var unfolded: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += String(line.dropFirst())
            } else {
                unfolded.append(line)
            }
        }

        var results: [AgendaEvent] = []
        var properties: [String: (parameters: [String: String], value: String)] = [:]
        var insideEvent = false

        for line in unfolded {
            if line.uppercased() == "BEGIN:VEVENT" {
                insideEvent = true
                properties = [:]
                continue
            }
            if line.uppercased() == "END:VEVENT" {
                if let event = makeEvent(properties) {
                    results.append(event)
                }
                insideEvent = false
                properties = [:]
                continue
            }
            guard insideEvent, let colon = line.firstIndex(of: ":") else { continue }

            let left = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let pieces = left.split(separator: ";", omittingEmptySubsequences: false)
            guard let first = pieces.first else { continue }
            let name = String(first).uppercased()
            var parameters: [String: String] = [:]

            for piece in pieces.dropFirst() {
                let pair = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if pair.count == 2 {
                    parameters[String(pair[0]).uppercased()] =
                        String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            if properties[name] == nil {
                properties[name] = (parameters, value)
            }
        }

        var seen = Set<String>()
        return results
            .sorted { $0.startDate < $1.startDate }
            .filter { seen.insert($0.uid).inserted }
    }

    private static func makeEvent(
        _ properties: [String: (parameters: [String: String], value: String)]
    ) -> AgendaEvent? {
        guard let rawStart = properties["DTSTART"],
              let start = parseDate(rawStart.value, parameters: rawStart.parameters) else {
            return nil
        }

        let title = decodeText(properties["SUMMARY"]?.value ?? "Wydarzenie")
        let rawUID = decodeText(properties["UID"]?.value ?? "")
        let uid = rawUID.isEmpty
            ? "\(title)|\(Int(start.timeIntervalSince1970))"
            : rawUID

        let end: Date
        if let rawEnd = properties["DTEND"],
           let parsedEnd = parseDate(rawEnd.value, parameters: rawEnd.parameters) {
            end = parsedEnd
        } else {
            let isAllDay = rawStart.parameters["VALUE"]?.uppercased() == "DATE"
                || rawStart.value.count == 8
            end = start.addingTimeInterval(isAllDay ? 86_400 : 3_600)
        }

        let description = decodeText(properties["DESCRIPTION"]?.value ?? "")
        return AgendaEvent(
            uid: uid,
            title: title.isEmpty ? "Wydarzenie" : title,
            startDate: start,
            endDate: max(end, start.addingTimeInterval(60)),
            notes: description
        )
    }

    private static func parseDate(
        _ raw: String,
        parameters: [String: String]
    ) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        if value.hasSuffix("Z") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }

            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return formatter.date(from: value)
        }

        if let tzid = parameters["TZID"], let zone = TimeZone(identifier: tzid) {
            formatter.timeZone = zone
        } else {
            formatter.timeZone = .current
        }

        if value.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
        } else if value.count == 13 {
            formatter.dateFormat = "yyyyMMdd'T'HHmm"
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return formatter.date(from: value)
    }

    private static func decodeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}