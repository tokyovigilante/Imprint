import Foundation
import Harness
import LoggerAPI

private struct InternalConfig: Codable {
    var ui: UI
}

struct UI: Codable {
    var path: String
    var debugMode: Bool
}

class SettingsController {

    static let shared = SettingsController()

    private var _internalConfig: InternalConfig

    public var ui: UI {
        return _internalConfig.ui
    }

    private init () {
        _internalConfig = InternalConfig(
                ui: UI(
                       path: LocalStorage.appSupportFolderURL.appendingPathComponent("UI").path,
                       debugMode: false
                )
        )
        watchConfig()
        if !load() {
            _ = save()
        }
    }

    func watchConfig () {
        let configURL = LocalStorage.configURL
        do {
            try FSEvents.shared.watch(
                item: configURL,
                types: [.modify, .delete],
                watcher: self)
            { config, fsevents, event in
                if event.type == .modify {
                    Log.debug("Config changed, reloading")
                    _ = config.load()
                }
            }
        } catch {
            Log.error("\(error)")
        }
    }

    func load () -> Bool {
        let configURL = LocalStorage.configURL
        let decoder = JSONDecoder()
        do {
            _internalConfig = try decoder.decode(InternalConfig.self, from: Data(contentsOf: configURL))
        } catch {
            Log.error("Config load from \(configURL.path) failed: \(error.localizedDescription)")
            return false
        }
        Log.verbose("Loaded config from \(configURL.path)")
        return true
    }

    func save () -> Bool {
        let configURL = LocalStorage.configURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let configJSON = try encoder.encode(_internalConfig)
            try LocalStorage.createContainingFolder(for: configURL)
            try configJSON.write(to: configURL)
        } catch {
            Log.error("Config save failed: \(error.localizedDescription)")
            return false
        }
        Log.verbose("Wrote config to \(configURL.path)")
        return true
    }

}
