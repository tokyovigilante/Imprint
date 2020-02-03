import AEXML
import Airframe
import CWebKitWPE
import Foundation
import Harness
import LoggerAPI

class UIController {

    private let _window: AirframeWindow
    private let _view: WPEView

    #if os(Linux)
        private let _renderManager: RenderManager
        private let _context: WPEContext
    #endif

    var resourceCallback: ((String) -> (Data?))? = nil

    init? (debug: Bool = false) {

#if os(Linux)
        guard let window = WaylandWSIWindow(title: "Imprint", appID: "com.testtoast.Imprint") else {
            Log.error("WSI Window creation failed")
            return nil
        }
        _window = window

        guard let renderManager = RenderManager(window: window) else {
            Log.error("Render manager creation failed")
            return nil
        }
        _renderManager = renderManager

        guard let context = WPEContext(window: window, debug: debug)  else {
            Log.error("WebKit context creation failed")
            return nil
        }
        _context = context

        guard let view = WPEView(context: context) else {
            Log.error("Base view creation failed")
            return nil
        }
        _view = view

        view.frameUpdateCallback = self.uiFrameUpdateCallback
        window.resizeCallback = self.resizeWindowCallback
        window.enteredCallback = self.windowEnteredCallback
        window.closeCallback = self.closeWindowCallback
        window.keyCallback = self.keyboardButtonCallback

#elseif os(OSX)

        guard let window = MacWSIWindow() else {
            return nil
        }
#endif
        registerURICallback()
    }

#if os(Linux)
    private func pointerMotionCallback (window: WaylandWSIWindow, event: InputPointerEvent) {
        _view.pointerMotion(event: event)
    }

    private func pointerButtonCallback (window: WaylandWSIWindow, event: InputPointerEvent) {
        _view.pointerButton(event: event)
    }

    private func pointerAxisCallback (window: WaylandWSIWindow, event: InputAxisEvent) {
        _view.pointerAxis(event: event)
    }

    private func keyboardButtonCallback (window: WaylandWSIWindow, event: InputKeyboardEvent) {
        DispatchQueue.main.async {
            self.process(key: event)
        }
    }

    private func process (key event: InputKeyboardEvent) {
        // Intercept globals
        var handled = false

        switch Int32(event.keyCode) {
        case XKB_KEY_o:
            if event.pressed && event.modifiers == InputModifier.control {
                //self.showOpenDialog()
            }
        case XKB_KEY_c:
            if event.pressed && event.modifiers == InputModifier.control {
                handled = true
                exit(0)
            }
        default:
            handled = false
            //Log.debug("Unhandled: \(String(describing: event))")
        }
        if !handled {
            _view.keyButton(event: event)
        }
        /*if _browserFocused {
            browserView.keyButton(window: window, event: event)
        } else {
            uiView.keyButton(window: window, event: event)
        }*/
    }

    private func windowEnteredCallback (window: WaylandWSIWindow, metrics: OutputMetrics) {
        _view.scaleFactor = Double(metrics.scaleFactor)
        Log.debug("Set WPE scale to \(metrics.scaleFactor)")
    }

    private func resizeWindowCallback (window: WaylandWSIWindow) {
        let width = UInt32(window.width)
        let height = UInt32(window.height)
        _view.setView(width: width, height: height)
        Log.debug("""
                Set WPE size to \
                \(window.pixelWidth)x\(window.pixelHeight)@\(window.scaleFactor)
                """)
    }

    private func closeWindowCallback (window: WaylandWSIWindow) {
        exit(0)
    }
#endif

    private func uiFrameUpdateCallback (image: WebViewImage) {
        _renderManager.updateUI(image: image)
    }

    private func registerURICallback () {
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
#if os(Linux)
        _context.connectURIHandler(for: "imprint", data: unsafeSelf, callback: handleImprintRequest)
#endif
    }

    func load(url: URL) {
        Log.info("Loading UI from \(url.path)")
        _view.load(url: url)
    }

    func handleUI(request: String) -> (mimeType: String, data: Data)? {
        Log.verbose("Got request for \(request)")

        let uiRequestURL = URL(fileURLWithPath: SettingsController.shared.ui.path)
                .appendingPathComponent(request)
        Log.verbose("Attempting load from \(uiRequestURL)")
        let pathExtension = uiRequestURL.pathExtension
        let mimeType = MimeTypes[pathExtension] ?? "application/octet-stream"
        Log.verbose("Got \(mimeType) for \(pathExtension)")

        guard let uiData = resourceCallback?(request) else {
            Log.error("Load failed for \(uiRequestURL))")
            return nil
        }
        Log.verbose("Loaded \(uiData.count) bytes from \(uiRequestURL)")

        if pathExtension == "html" || pathExtension == "xhtml" {
            measure {
                let data = XMLSanitizer.reparse(data: uiData)
            }
            return (mimeType: "text/html", data: XMLSanitizer.reparse(data: uiData))
        } else {
            return (mimeType: mimeType, data: uiData)
        }
    }



    func inject(css: String) {
        _view.inject(css: css)
    }

}

fileprivate var handleImprintRequest: URIHandler = { data, url, completion in

    let controller = Unmanaged<UIController>.fromOpaque(data).takeUnretainedValue()

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host else {
        Log.error("Invalid API request \(url)")
        completion(nil, nil)
        return
    }
    Log.verbose("\(url) requested")
    let pathComponents = url.pathComponents
    if pathComponents.isEmpty || host != "imprint" {
        Log.error("Invalid API request \(url)")
        completion(nil, nil)
        return
    }
    let request: String
    let response: (mimeType: String, data: Data)?
    request = pathComponents[1...].joined(separator: "/")
    response = controller.handleUI(request: request)
    completion(response?.mimeType, response?.data)
}
