import Foundation

struct RepoInfo: Codable, Equatable {
    var name: String
    var version: String?
    var date: String?
    var body: String?
    var error: String?
}

struct RepoConfig: Codable, Equatable {
    var name: String
    var source: String // "manual" or "brew"
    var cask: String?
    var tags: [String]?
    var isFavorite: Bool?
}

struct AppConfig: Codable {
    var repos: [RepoConfig]
    var refreshMinutes: Int
    var sortBy: String // "name" or "date"
    var showOwner: Bool
    var showIcons: Bool?
    var showNewIndicator: Bool?
    var newIndicatorDays: Int?
    var menuLayout: String? // "columns" | "cards" | "tags"
    var menuFontSize: CGFloat?
    
    enum CodingKeys: String, CodingKey {
        case repos
        case refreshMinutes = "refresh_minutes"
        case sortBy = "sort_by"
        case showOwner = "show_owner"
        case showNewIndicator = "show_new_indicator"
        case newIndicatorDays = "new_indicator_days"
        case menuLayout = "menu_layout"
        case menuFontSize = "menu_font_size"
    }
    
    // Legacy key for migration from is_compact_mode
    private enum LegacyKeys: String, CodingKey {
        case isCompactMode = "is_compact_mode"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        refreshMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? Constants.defaultRefreshIntervalMinutes
        sortBy = try container.decodeIfPresent(String.self, forKey: .sortBy) ?? "name"
        showOwner = try container.decodeIfPresent(Bool.self, forKey: .showOwner) ?? false
        showNewIndicator = try container.decodeIfPresent(Bool.self, forKey: .showNewIndicator)
        newIndicatorDays = try container.decodeIfPresent(Int.self, forKey: .newIndicatorDays)
        menuLayout = try container.decodeIfPresent(String.self, forKey: .menuLayout)
        menuFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .menuFontSize)
        
        // Migration: convert legacy is_compact_mode → menuFontSize
        if menuFontSize == nil {
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            if let isCompact = try? legacy?.decodeIfPresent(Bool.self, forKey: .isCompactMode), isCompact == true {
                menuFontSize = 11.0
            }
        }
    }
    
    init() {
        self.repos = [
            RepoConfig(name: "nad-bit/Mino", source: "brew", cask: "nad-bit/tap/mino", isFavorite: true),
            RepoConfig(name: "objective-see/LuLu", source: "brew", cask: "lulu"),
            RepoConfig(name: "exelban/stats", source: "brew", cask: "stats"),
            RepoConfig(name: "alienator88/Sentinel", source: "brew", cask: "alienator88-sentinel"),
            RepoConfig(name: "alienator88/Pearcleaner", source: "brew", cask: "pearcleaner"),
            RepoConfig(name: "Caldis/Mos", source: "manual"),
            RepoConfig(name: "homielab/mountmate", source: "brew", cask: "mountmate"),
            RepoConfig(name: "ronitsingh10/FineTune", source: "brew", cask: "finetune"),
            RepoConfig(name: "jsattler/BetterCapture", source: "brew", cask: "jsattler/tap/bettercapture"),
            RepoConfig(name: "66HEX/frame", source: "manual"),
            RepoConfig(name: "paolorotolo/GHomeBar", source: "manual")
        ]
        self.refreshMinutes = Constants.defaultRefreshIntervalMinutes
        self.sortBy = "name"
        self.showOwner = false
        self.showNewIndicator = true
        self.newIndicatorDays = 7
        self.menuLayout = "columns"
        self.menuFontSize = Constants.menuBaseFontSize
    }
}
