import Foundation

enum Constants {
    // Timing Constants
    static let defaultRefreshIntervalMinutes: Int = 360  // 6 hours
    static let menuUpdateBatchDelaySeconds: Double = 0.3 // 300ms
    static let countdownTimerIntervalSeconds: TimeInterval = 60 // 1 minute
    
    // Performance Constants
    static let threadPoolMaxWorkers: Int = 5
    static let httpRequestTimeoutSeconds: TimeInterval = 10
    static let httpMaxRetries: Int = 3
    
    // UI Constants
    static let newReleaseThresholdDays: Int = 7 // Fallback default, overridden by config
    static let newReleaseIndicator = "✦"  // Monochromatically neutral sparkle
    
    // System Constants
    static let launchAgentLabel = "com.nad.mino"
    static let homebrewPaths = [
        "/opt/homebrew/bin/brew",  // Apple Silicon
        "/usr/local/bin/brew"      // Intel
    ]
    
    // API Constants
    static let githubAPIBaseURL = "https://api.github.com"
    static let userAgent = "Swift-AppKit-Mino"
}
