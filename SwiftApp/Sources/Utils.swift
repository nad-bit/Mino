import Cocoa

class Utils {
    static func parseDate(dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    static func getReleaseAge(dateString: String?) -> (label: String, seconds: Double) {
        guard let releaseDate = parseDate(dateString: dateString) else {
            return ("N/A", .infinity)
        }
        
        let secondsDiff = Date().timeIntervalSince(releaseDate)
        
        if secondsDiff < 0 {
            return ("0 " + Translations.get("unitMin"), 0)
        }
        
        if secondsDiff < 3600 {
            let minutes = max(1, Int(round(secondsDiff / 60)))
            return ("\(minutes) " + Translations.get("unitMin"), secondsDiff)
        } else if secondsDiff < 86400 {
            let hours = max(1, Int(floor(secondsDiff / 3600)))
            let hoursLabel = hours == 1 ? Translations.get("unitHour") : Translations.get("unitHoursPlural")
            return ("\(hours) \(hoursLabel)", secondsDiff)
        } else {
            let daysFloat = secondsDiff / 86400
            let daysCount = max(1, Int(floor(daysFloat)))
            let daysLabel = daysCount == 1 ? Translations.get("unitDay") : Translations.get("days")
            return ("\(daysCount) \(daysLabel)", secondsDiff)
        }
    }
    
    static func getGitHubRepoFromClipboard() -> String? {
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            // GitHub usernames and repos can only contain alphanumeric characters, hyphens, underscores, and periods.
            // This strictly filters out typographic quotes (“, ”) and other surrounding sentence punctuation.
            let regex = try? NSRegularExpression(pattern: "(?:github\\.com/)?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)")
            let range = NSRange(location: 0, length: clipboard.utf16.count)
            if let match = regex?.firstMatch(in: clipboard, options: [], range: range) {
                if let r = Range(match.range(at: 1), in: clipboard) {
                    let candidate = String(clipboard[r]).replacingOccurrences(of: ".git", with: "")
                    if candidate.split(separator: "/").count == 2 {
                        return candidate
                    }
                }
            }
        }
        return nil
    }
}
