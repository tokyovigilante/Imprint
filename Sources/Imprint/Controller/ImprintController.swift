import EPUBCore
import Foundation
import Harness
import LoggerAPI
import ZipReader

fileprivate var displayCSS = """
    body {
        width: 700px;
        column-width: 700px;
        margin: 0 auto;
        line-height: 1.5em;
    }
"""

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
        //_uiController.loadUI()

        if CommandLine.arguments.count < 2 {
            Log.error("Missing book path")
            exit(-1)
        }

        let bookPath = CommandLine.arguments[1]
        let bookURL = URL(fileURLWithPath: bookPath)

        Log.info("Opening \(bookURL.path)")
        guard let reader = FREpubParser(bookURL: bookURL) else {
            Log.error("EPUB open failed")
            exit(-1)
        }
        let book: FRBook
        do {
            book = try reader.readEpub()
        } catch {
            Log.error("EPUB read failed")
            exit(-1)
        }

        _uiController.inject(css: displayCSS)

        _uiController.resourceCallback = { path in
            do {
                let zipResource = try reader.readResource(path: path)
                return zipResource.data
            } catch let error {
                Log.error(error.localizedDescription)
                return nil
            }
        }

        guard let firstPage = book.spine.spineReferences[0].resource.fullHref else {
            Log.error("Could not get reference for book section")
            return nil
        }
        guard let firstPageURL = URL(string: firstPage, relativeTo: URL(string: "imprint://imprint/zipresource")!) else {
            Log.error("Could not create URL for \(firstPage)")
            return nil
        }
        Log.info("Loading from \(firstPageURL.path)")
        uiController.load(url: firstPageURL)

    }

}
