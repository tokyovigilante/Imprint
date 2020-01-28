import EPUBCore
import Foundation
import Harness
import LoggerAPI
import ZipReader

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

        let timer = PrecisionTimer()
        do {
            for spineItem in book.spine.spineReferences {
                let zipResource = try! reader.readResource(path: spineItem.resource.fullHref)
                guard let htmlString = String(data: zipResource.data, encoding: .utf8) else {
                    Log.error("Blown it")
                    exit(-1)
                }
                _uiController.load(html: htmlString)
                break
                //Log.info(htmlString)
            }
        }
        Log.info("Took \(timer.elapsed) sec")
    }

}
