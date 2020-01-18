import EPUBCore
import Foundation
import Harness
import LoggerAPI

try! ConsoleManager.configureLogging(.debug, detailed: true, destinations: [.console], async: false)

#if os(Linux)
ConsoleManager.redirectGLibLogging(for: [
        "GLib",
        "GLib-GObject",
        "GThread",
        "Gnome",
        "libgnome",
        "gmime",
])
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

Log.info(String(describing: book.tableOfContents))

