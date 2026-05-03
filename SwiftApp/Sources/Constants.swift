import Foundation

enum Constants {
    // Timing Constants
    static let defaultRefreshIntervalMinutes: Int = 360  // 6 hours
    static let menuUpdateBatchDelaySeconds: Double = 0.3 // 300ms
    static let interactiveControlDelaySeconds: Double = 0.5 // 500ms
    static let countdownTimerIntervalSeconds: TimeInterval = 60 // 1 minute
    
    // Performance Constants
    static let threadPoolMaxWorkers: Int = 5
    static let httpRequestTimeoutSeconds: TimeInterval = 10
    static let httpMaxRetries: Int = 3
    
    // UI Constants
    static let newReleaseThresholdDays: Int = 7 // Fallback default, overridden by config
    static let menuHeaderFooterHeight: CGFloat = 32.0
    static let menuMinWidth: CGFloat = 320.0
    static let menuDefaultWidth: CGFloat = 400.0
    static let menuMaxWidth: CGFloat = 500.0
    static let tagCloudMaxTags: Int = 27
    static let menuBaseFontSize: CGFloat = 14.0
    static let menuFontSizeMin: CGFloat = 10.0
    static let menuFontSizeMax: CGFloat = 18.0
    
    // System Constants
    static let launchAgentLabel = "com.nad.mino"
    static let homebrewPaths = [
        "/opt/homebrew/bin/brew",  // Apple Silicon
        "/usr/local/bin/brew"      // Intel
    ]
    
    // API Constants
    static let githubAPIBaseURL = "https://api.github.com"
    static let userAgent = "Swift-AppKit-Mino"
    static let githubClientID = "Ov23liW2PRuycPFESEpX"
}
