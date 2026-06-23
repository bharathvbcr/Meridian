import Foundation

enum ICSGenerator {

    // MARK: - Date Formatter

    private static let icsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dtstampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Public API

    /// Generates a valid VCALENDAR/VEVENT ICS string.
    ///
    /// - Parameters:
    ///   - title: The event summary / title.
    ///   - startDate: The start date/time of the event.
    ///   - durationMinutes: Duration of the event in minutes.
    ///   - timeZoneId: IANA time zone identifier (e.g. "America/New_York").
    ///   - notes: Optional description / notes for the event.
    /// - Returns: A well-formed ICS string.
    static func generateICS(
        title: String,
        startDate: Date,
        durationMinutes: Int,
        timeZoneId: String,
        notes: String? = nil
    ) -> String {
        let timeZone = TimeZone(identifier: timeZoneId) ?? TimeZone.current

        // Format DTSTART and DTEND in the event's local timezone
        icsDateFormatter.timeZone = timeZone
        let dtStart = icsDateFormatter.string(from: startDate)
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let dtEnd = icsDateFormatter.string(from: endDate)

        // DTSTAMP is always UTC
        let dtstamp = dtstampFormatter.string(from: Date())

        // Generate a stable UID from title + startDate
        let uid = generateUID(title: title, startDate: startDate)

        // Escape special characters in text fields per RFC 5545
        let escapedTitle = escapeICSText(title)
        let escapedNotes = notes.map { escapeICSText($0) }

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Meridian//MeridianApp//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(dtstamp)",
            "DTSTART;TZID=\(timeZoneId):\(dtStart)",
            "DTEND;TZID=\(timeZoneId):\(dtEnd)",
            "SUMMARY:\(escapedTitle)"
        ]

        if let escapedNotes {
            lines.append("DESCRIPTION:\(escapedNotes)")
        }

        lines += [
            "END:VEVENT",
            "END:VCALENDAR"
        ]

        // RFC 5545 requires CRLF line endings
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the ICS content to a temporary file and returns its URL.
    ///
    /// - Parameters:
    ///   - title: The event summary / title.
    ///   - startDate: The start date/time of the event.
    ///   - durationMinutes: Duration of the event in minutes.
    ///   - timeZoneId: IANA time zone identifier.
    /// - Returns: A file URL pointing to the temporary `.ics` file.
    /// - Throws: If writing the file to disk fails.
    static func exportURL(
        title: String,
        startDate: Date,
        durationMinutes: Int,
        timeZoneId: String
    ) throws -> URL {
        let icsString = generateICS(
            title: title,
            startDate: startDate,
            durationMinutes: durationMinutes,
            timeZoneId: timeZoneId,
            notes: nil
        )

        let sanitizedTitle = title
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = sanitizedTitle.isEmpty ? "event" : sanitizedTitle
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("\(fileName).ics")

        guard let data = icsString.data(using: .utf8) else {
            throw ICSGeneratorError.encodingFailed
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Private Helpers

    /// Produces a deterministic UID per RFC 5545 using title + startDate epoch.
    private static func generateUID(title: String, startDate: Date) -> String {
        let epoch = Int(startDate.timeIntervalSince1970)
        let sanitized = title
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "-")
        return "\(epoch)-\(sanitized)@meridian.app"
    }

    /// Escapes commas, semicolons, and backslashes per RFC 5545 §3.3.11.
    private static func escapeICSText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}

// MARK: - Errors

enum ICSGeneratorError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode ICS content as UTF-8 data."
        }
    }
}
