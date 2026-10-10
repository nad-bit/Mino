import Foundation

struct ReleaseAsset: Codable, Equatable {
    var name: String
    var size: Int64?
    var downloadURL: String
    var isSourceArchive: Bool
    var expectedSHA256: String? = nil
}

struct RepoInfo: Codable, Equatable {
    var name: String
    var version: String?
    var date: String?
    var body: String?
    var error: String?
    var assets: [ReleaseAsset]?
    var errorCode: Int? = nil
    var isNotModified: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case name, version, date, body, error, assets, errorCode
    }
}

struct RepoConfig: Codable, Equatable {
    var name: String
    var source: String // "manual" or "brew"
    var cask: String?
    var tags: [String]?
    var repoDescription: String?
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
    var downloadPath: String?
    var beerHandleEnabled: Bool?
    var menuScale: Double?
    
    enum CodingKeys: String, CodingKey {
        case repos
        case refreshMinutes = "refresh_minutes"
        case sortBy = "sort_by"
        case showOwner = "show_owner"
        case showNewIndicator = "show_new_indicator"
        case newIndicatorDays = "new_indicator_days"
        case menuLayout = "menu_layout"
        case menuFontSize = "menu_font_size"
        case downloadPath = "download_path"
        case beerHandleEnabled = "beer_handle_enabled"
        case menuScale = "menu_scale"
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
        downloadPath = (try container.decodeIfPresent(String.self, forKey: .downloadPath)) ?? "~/Desktop"
        beerHandleEnabled = try container.decodeIfPresent(Bool.self, forKey: .beerHandleEnabled)
        menuScale = try container.decodeIfPresent(Double.self, forKey: .menuScale)
        
        // Migration: convert legacy is_compact_mode → menuFontSize
        if menuFontSize == nil {
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            if let isCompact = try? legacy?.decodeIfPresent(Bool.self, forKey: .isCompactMode), isCompact == true {
                menuFontSize = 16.0
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
            RepoConfig(name: "darrylmorley/whatcable", source: "manual"),
            RepoConfig(name: "homielab/mountmate", source: "brew", cask: "mountmate"),
            RepoConfig(name: "ronitsingh10/FineTune", source: "brew", cask: "finetune"),
            RepoConfig(name: "jsattler/BetterCapture", source: "brew", cask: "bettercapture"),
            RepoConfig(name: "Feng6611/mac-command-reopen", source: "manual"),
            RepoConfig(name: "paolorotolo/GHomeBar", source: "manual"),
            RepoConfig(name: "aagedal/Aagedal-Media-Converter", source: "manual"),
            RepoConfig(name: "Santosh7017/AndroidFileSync", source: "manual"),
            RepoConfig(name: "gangz1o/Clipaste", source: "manual"),
            RepoConfig(name: "jaywcjlove/awesome-swift-macos-apps", source: "manual"),
            RepoConfig(name: "nickybmon/OpenEmu-Silicon", source: "manual"),
            RepoConfig(name: "ganeshmshetty/openclip", source: "manual"),
            RepoConfig(name: "Homebrew/brewui", source: "brew", cask: "homebrew-app"),
            RepoConfig(name: "robbietilton/Compositor", source: "brew", cask: "robbietilton-compositor"),
            RepoConfig(name: "vorssaint/vorssaint-utils", source: "brew", cask: "vorssaint"),
            RepoConfig(name: "Licoy/StrokeMouse", source: "brew", cask: "licoy/tap/strokemouse"),
            RepoConfig(name: "USBridge-Technologies/USBridge-Remote", source: "manual"),
            RepoConfig(name: "TokTok/qTox", source: "manual"),
            RepoConfig(name: "aimen08/noty", source: "manual"),
RepoConfig(name: "apedley/transmogrify", source: "manual"),
            RepoConfig(name: "idawnlight/ShichiZip", source: "brew", cask: "shichizip")
        ]
        self.refreshMinutes = Constants.defaultRefreshIntervalMinutes
        self.sortBy = "name"
        self.showOwner = false
        self.showNewIndicator = true
        self.newIndicatorDays = 7
        self.menuLayout = "cards"
        self.menuFontSize = Constants.menuBaseFontSize
        self.downloadPath = "~/Desktop"
        self.beerHandleEnabled = true
        self.menuScale = 1.0
    }
}
