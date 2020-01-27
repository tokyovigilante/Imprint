import Foundation
import Harness
import LoggerAPI

class ImprintController {

    private let _uiController: UIController

    init? () {

        // _ = ImprintConfig.shared

        do {
            try FSEvents.shared.startWatching()
        } catch let FSEventsError.startupFailure(message) {
            Log.error("FS monitoring startup failed: \(message)")
        } catch {
            Log.error("Unknown error: \(error)")
        }

        guard let uiController = UIController(debug: true) else {
            return nil
        }
        _uiController = uiController
        _uiController.loadUI()
    }

}
