import EPUBCore
import Foundation
import Harness
import LoggerAPI
import ZipReader

try! ConsoleManager.configureLogging(.debug, detailed: true, destinations: [.console], async: true)

#if os(Linux)

ConsoleManager.redirectGLibLogging(for: [
        "GLib",
        "GLib-GObject",
        "GThread",
        "Gnome",
        "libgnome",
        "gmime",
])


signal(SIGINT) { _ in
    //merlin.stop()
    exit(0)
}

let controller = ImprintController()

eventLoopRun()

#elseif os(OSX)
import Cocoa

guard let window = MacWSIWindow() else {
    exit(-1)
}

let delegate = AppDelegate(window: window)

let application = NSApplication.shared
//let icon = NSImage(contentsOfFile: "")
application.applicationIconImage = icon
application.delegate = delegate
application.run()
#endif

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
        let zipResource = try reader.readResource(path: spineItem.resource.fullHref)
        guard let htmlString = String(data: zipResource.data, encoding: .utf8) else {
            Log.error("Blown it")
            exit(-1)
        }
        //Log.info(htmlString)
    }
}
Log.info("Took \(timer.elapsed) sec")
