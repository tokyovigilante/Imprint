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

