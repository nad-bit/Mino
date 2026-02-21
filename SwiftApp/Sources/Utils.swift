import Foundation

class Utils {
    static func getReleaseAge(dateString: String?) -> (label: String, seconds: Double) {
        guard let dateString = dateString else {
            return ("N/A", .infinity)
        }
        
        // El formato de GitHub es ISO8601, ej. "2023-10-18T15:00:00Z"
        let formatter = ISO8601DateFormatter()
        guard let releaseDate = formatter.date(from: dateString) else {
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
}
