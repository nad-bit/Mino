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
    
    static func convertMarkdownToHTML(_ markdown: String) -> String {
        // CSS styles for table rendering
        let css = "<style>table { border-collapse: collapse; width: 100%; margin: 12px 0; } th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 10px; text-align: left; } th { background-color: rgba(128,128,128,0.15); font-weight: bold; }</style>"
        
        var body = css
        let lines = markdown.components(separatedBy: .newlines)
        var inCodeBlock = false
        var inList = false
        var inOrderedList = false
        var inTable = false
        var tableHeaderCells: [String] = []
        var tableRows: [[String]] = []
        
        func closeListIfNeeded() {
            if inList {
                body += "</ul>\n"
                inList = false
            }
            if inOrderedList {
                body += "</ol>\n"
                inOrderedList = false
            }
        }
        
        func closeTableIfNeeded() {
            if inTable {
                // NOTE: <table> must come BEFORE <thead>
                body += "<table>\n"
                if !tableHeaderCells.isEmpty {
                    body += "<thead>\n<tr>\n"
                    for cell in tableHeaderCells {
                        body += "<th>\(processInlineMarkdown(cell))</th>\n"
                    }
                    body += "</tr>\n</thead>\n"
                }
                body += "<tbody>\n"
                for row in tableRows {
                    body += "<tr>\n"
                    for cell in row {
                        body += "<td>\(processInlineMarkdown(cell))</td>\n"
                    }
                    body += "</tr>\n"
                }
                body += "</tbody>\n</table>\n"
                inTable = false
                tableHeaderCells = []
                tableRows = []
            }
        }
        
        var i = 0
        while i < lines.count {
            let line = lines[i]
            
            // Code blocks
            if line.trimmed().hasPrefix("```") {
                closeListIfNeeded()
                closeTableIfNeeded()
                if inCodeBlock {
                    body += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    body += "<pre><code>"
                    inCodeBlock = true
                }
                i += 1
                continue
            }
            
            if inCodeBlock {
                body += line.escapingHTML() + "\n"
                i += 1
                continue
            }
            
            // Detect table start
            let trimmedLine = line.trimmed()
            if trimmedLine.hasPrefix("|") && trimmedLine.hasSuffix("|") {
                var isTable = false
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1].trimmed()
                    if nextLine.hasPrefix("|") && nextLine.hasSuffix("|") {
                        let stripped = nextLine.replacingOccurrences(of: "|", with: "")
                                               .replacingOccurrences(of: "-", with: "")
                                               .replacingOccurrences(of: ":", with: "")
                                               .replacingOccurrences(of: " ", with: "")
                        if stripped.isEmpty && nextLine.contains("-") {
                            isTable = true
                        }
                    }
                }
                
                if isTable {
                    closeListIfNeeded()
                    inTable = true
                    tableHeaderCells = parseTableRow(line)
                    i += 2 // skip header and separator line
                    continue
                }
            }
            
            if inTable {
                if trimmedLine.hasPrefix("|") && trimmedLine.hasSuffix("|") {
                    let cells = parseTableRow(line)
                    tableRows.append(cells)
                    i += 1
                    continue
                } else {
                    closeTableIfNeeded()
                }
            }
            
            // Headings
            if trimmedLine.hasPrefix("#") {
                closeListIfNeeded()
                closeTableIfNeeded()
                var level = 0
                while level < trimmedLine.count && trimmedLine[trimmedLine.index(trimmedLine.startIndex, offsetBy: level)] == "#" {
                    level += 1
                }
                let remainingText = String(trimmedLine.dropFirst(level)).trimmed()
                if level >= 1 && level <= 6 {
                    body += "<h\(level)>\(processInlineMarkdown(remainingText))</h\(level)>\n"
                    i += 1
                    continue
                }
            }
            
            // Lists
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                closeTableIfNeeded()
                if !inList {
                    closeListIfNeeded()
                    body += "<ul>\n"
                    inList = true
                }
                let itemText = String(trimmedLine.dropFirst(2)).trimmed()
                body += "<li>\(processInlineMarkdown(itemText))</li>\n"
                i += 1
                continue
            }
            
            // Ordered Lists
            let orderedListPattern = "^\\d+\\.\\s+(.*)"
            if let regex = try? NSRegularExpression(pattern: orderedListPattern),
               let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
                closeTableIfNeeded()
                if !inOrderedList {
                    closeListIfNeeded()
                    body += "<ol>\n"
                    inOrderedList = true
                }
                let r = Range(match.range(at: 1), in: trimmedLine)!
                let itemText = String(trimmedLine[r]).trimmed()
                body += "<li>\(processInlineMarkdown(itemText))</li>\n"
                i += 1
                continue
            }
            
            // Empty lines
            if trimmedLine.isEmpty {
                closeListIfNeeded()
                closeTableIfNeeded()
                body += "<p></p>\n"
                i += 1
                continue
            }
            
            // Paragraph or plain line
            closeListIfNeeded()
            closeTableIfNeeded()
            body += "<p>\(processInlineMarkdown(line))</p>\n"
            i += 1
        }
        
        closeListIfNeeded()
        closeTableIfNeeded()
        
        return body
    }
    
    private static func parseTableRow(_ line: String) -> [String] {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        if parts.count <= 1 { return [] }
        var result: [String] = []
        let startIndex = line.hasPrefix("|") ? 1 : 0
        let endIndex = line.hasSuffix("|") ? parts.count - 1 : parts.count
        for j in startIndex..<endIndex {
            result.append(String(parts[j]).trimmed())
        }
        return result
    }
    
    private static func processInlineMarkdown(_ text: String) -> String {
        var result = text.escapingHTML()
        
        // Convert links: [text](url) -> <a href="url">text</a>
        let linkPattern = "\\[([^\\]]*?)\\]\\(([^\\)]*?)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                guard let textRange = Range(match.range(at: 1), in: result),
                      let urlRange = Range(match.range(at: 2), in: result),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                let linkText = String(result[textRange])
                let linkUrl = String(result[urlRange])
                let replacement = "<a href=\"\(linkUrl)\">\(linkText)</a>"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        
        // Convert bold: **text** -> <strong>text</strong>
        let boldPattern = "\\*\\*(.*?)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                guard let textRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                let boldText = String(result[textRange])
                let replacement = "<strong>\(boldText)</strong>"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        
        // Convert italic: *text* -> <em>text</em>
        let italicPattern = "\\*(.*?)\\*"
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                guard let textRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                let italicText = String(result[textRange])
                let replacement = "<em>\(italicText)</em>"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        
        // Convert inline code: `code` -> <code>code</code>
        let codePattern = "`(.*?)`"
        if let regex = try? NSRegularExpression(pattern: codePattern) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                guard let textRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                let codeText = String(result[textRange])
                let replacement = "<code>\(codeText)</code>"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        
        return result
    }
}

extension String {
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func escapingHTML() -> String {
        var result = self
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
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
            context.duration = Constants.defaultAnimationDuration // Fast but visible (user asked for fast)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) // Accelerate towards the icon
            
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
