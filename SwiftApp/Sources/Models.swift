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
    var isCompactMode: Bool?
    
    enum CodingKeys: String, CodingKey {
        case repos
        case refreshMinutes = "refresh_minutes"
        case sortBy = "sort_by"
        case showOwner = "show_owner"
        case showNewIndicator = "show_new_indicator"
        case newIndicatorDays = "new_indicator_days"
        case menuLayout = "menu_layout"
        case isCompactMode = "is_compact_mode"
    }
    
    init() {
        self.repos = [
            RepoConfig(name: "nad-bit/Mino", source: "manual"),
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
        self.showNewIndicator = false
        self.newIndicatorDays = 7
        self.menuLayout = "columns"
        self.isCompactMode = false
    }
}
