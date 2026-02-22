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
}

struct AppConfig: Codable {
    var repos: [RepoConfig]
    var refreshMinutes: Int
    var sortBy: String // "name" or "date"
    var showOwner: Bool
    var showIcons: Bool?
    
    enum CodingKeys: String, CodingKey {
        case repos
        case refreshMinutes = "refresh_minutes"
        case sortBy = "sort_by"
        case showOwner = "show_owner"
        case showIcons = "show_icons"
    }
    
    init() {
        self.repos = [
            RepoConfig(name: "exelban/stats", source: "brew", cask: "stats"),
            RepoConfig(name: "p0deje/Maccy", source: "brew", cask: "maccy"),
            RepoConfig(name: "utmapp/UTM", source: "brew", cask: "utm"),
            RepoConfig(name: "objective-see/LuLu", source: "brew", cask: "lulu"),
            RepoConfig(name: "alienator88/Pearcleaner", source: "brew", cask: "pearcleaner"),
            RepoConfig(name: "alienator88/Sentinel", source: "brew", cask: "alienator88-sentinel"),
            RepoConfig(name: "upscayl/upscayl", source: "brew", cask: "upscayl"),
            RepoConfig(name: "jorio/BillyFrontier", source: "brew", cask: "billy-frontier"),
            RepoConfig(name: "Marginal/QLVideo", source: "brew", cask: "qlvideo"),
            RepoConfig(name: "paulpacifico/shutter-encoder", source: "brew", cask: "shutter-encoder"),
            RepoConfig(name: "xbmc/xbmc", source: "brew", cask: "kodi"),
            RepoConfig(name: "ONLYOFFICE/DesktopEditors", source: "brew", cask: "onlyoffice"),
            RepoConfig(name: "HandBrake/HandBrake", source: "brew", cask: "handbrake-app")
        ]
        self.refreshMinutes = Constants.defaultRefreshIntervalMinutes
        self.sortBy = "date"
        self.showOwner = false
        self.showIcons = false
    }
}
