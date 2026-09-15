import Foundation

enum BeerHandleDesign {
    case curved      // Classic beer mug D-shaped handle
    case rectangular // Simple rectangular handle with rounded corners
}

enum BeerHandleAnimation {
    case fade   // Simple fade in/out
    case slide  // Slide in from the right edge
}

enum Constants {
    // Timing Constants
    static let defaultRefreshIntervalMinutes: Int = 360  // 6 hours
    static let menuUpdateBatchDelaySeconds: Double = 0.3 // 300ms
    static let interactiveControlDelaySeconds: Double = 0.5 // 500ms
    static let countdownTimerIntervalSeconds: TimeInterval = 15 // 15 seconds
    
    // Performance Constants
    static let threadPoolMaxWorkers: Int = 30
    static let httpRequestTimeoutSeconds: TimeInterval = 30
    static let httpMaxRetries: Int = 3
    
    // UI Constants
    static let newReleaseThresholdDays: Int = 7 // Fallback default, overridden by config
    static let menuHeaderFooterHeight: CGFloat = 54.0
    static let menuMinWidth: CGFloat = 512.0
    static let menuDefaultWidth: CGFloat = 512.0
    static let menuMaxWidth: CGFloat = 512.0
    static let menuMaxHeight: CGFloat = 688.0
    static let notesWindowWidth: CGFloat = 640.0
    static let notesWindowHeight: CGFloat = 580.0
    static let tagCloudMaxTags: Int = 27
    static let menuBaseFontSize: CGFloat = 16.0
    static let menuFontSizeMin: CGFloat = 11.0
    static let menuFontSizeMax: CGFloat = 21.0
    static let popoverAnimates: Bool = false
    static let defaultAnimationDuration: TimeInterval = 0.15
    
    // Beer Handle (ASA) Constants
    static let beerHandleEnabled: Bool = true          // Master toggle for the handle
    static let beerHandleDesign: BeerHandleDesign = .curved  // .curved (D shape) or .rectangular
    static let beerHandleAnimation: BeerHandleAnimation = .slide // .fade or .slide
    static let beerHandleWidth: CGFloat = menuMaxWidth / 4 // Extends 1/4 of menu width to the right
    static let beerHandleThickness: CGFloat = menuHeaderFooterHeight // Tube thickness = header/footer height
    static let beerHandleMinHeight: CGFloat = menuMaxHeight - (2*menuHeaderFooterHeight) // Hide if menu shorter than its max height (2 * header+footer)
    static let beerHandleGapFromMenu: CGFloat = 1.0   // Horizontal gap between popover edge and handle
    static let beerHandleVerticalInset: CGFloat = menuHeaderFooterHeight // Inset from top/bottom of the scroll area (menuHeaderFooterHeight = 54.0)
    static let beerHandleCornerRadius: CGFloat = 14.0  // Corner radius for rectangular design
    static let beerHandleAnimationDuration: TimeInterval = 0.25
    static let beerHandleShowDebounce: TimeInterval = 0.3 // Debounce delay before showing the handle
    
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
