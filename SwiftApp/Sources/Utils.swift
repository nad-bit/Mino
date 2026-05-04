import Cocoa

class Utils {
    private static let isoFormatter = ISO8601DateFormatter()
    
    static func parseDate(dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        return isoFormatter.date(from: dateString)
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
    
    private static let githubUrlRegex = try? NSRegularExpression(pattern: "github\\.com/([A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+)")
    private static let githubExactRegex = try? NSRegularExpression(pattern: "^([A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+)$")

    static func getGitHubRepoFromClipboard() -> String? {
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            // Performance guard: Don't process massive clipboard contents
            if clipboard.count > 1000 { return nil }
                
            let text = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            
            // 1. Support the new smart brew syntax
            if text.lowercased().hasPrefix("brew:") {
                return text // Return the whole thing including brew:
            }
            
            // 2. Try finding a full GitHub URL in the string
            if let match = githubUrlRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               let r = Range(match.range(at: 1), in: text) {
                let candidate = String(text[r]).replacingOccurrences(of: ".git", with: "")
                if candidate.split(separator: "/").count == 2 {
                    return candidate
                }
            }
            
            // 3. Check if the ENTIRE string is "owner/repo" isolated.
            if let match = githubExactRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
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

extension NSWindow {
    func suckAndClose() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let statusItem = appDelegate.statusItem,
              let buttonWindow = statusItem.button?.window else {
            self.close()
            return
        }
        
        let targetFrame = buttonWindow.frame
        let originalFrame = self.frame
        
        // Ensure alpha is fully opaque initially
        self.alphaValue = 1.0
        
        // Fast, fluid animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15 // Fast but visible (user asked for fast)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn) // Accelerate towards the icon
            
            // Animate frame and alpha
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.close()
            // Reset state in case the window is reused
            self.setFrame(originalFrame, display: false)
            self.alphaValue = 1.0
        })
    }
}
