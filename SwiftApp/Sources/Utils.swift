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
            let text = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Try finding a full GitHub URL in the string (e.g., inside a sentence or rich text payload)
            // The owner portion strictly forbids periods to filter out app bundles like "Mino.app"
            let urlRegex = try? NSRegularExpression(pattern: "github\\.com/([A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+)")
            if let match = urlRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               let r = Range(match.range(at: 1), in: text) {
                let candidate = String(text[r]).replacingOccurrences(of: ".git", with: "")
                if candidate.split(separator: "/").count == 2 {
                    return candidate
                }
            }
            
            // 2. If no URL is found, check if the ENTIRE string is "owner/repo" isolated.
            // Using ^ and $ ensures we don't accidentally match local paths inside a longer text,
            // and the alphanumeric start ensures we reject starting slashes or periods like "./".
            let exactRegex = try? NSRegularExpression(pattern: "^([A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+)$")
            if let match = exactRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               let r = Range(match.range(at: 1), in: text) {
                let candidate = String(text[r]).replacingOccurrences(of: ".git", with: "")
                if candidate.split(separator: "/").count == 2 {
                    return candidate
                }
            }
        }
        return nil
    }
    
    static let appIconColor: NSColor = AppPersonality.color
}

