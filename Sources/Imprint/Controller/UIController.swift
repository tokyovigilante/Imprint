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
    /*private func pointerMotionCallback (window: WaylandWSIWindow, event: InputPointerEvent) {
        if event.y <= 72 {
            _browserFocused = false
            uiView.pointerMotion(window: window, event: event)
        } else {
            _browserFocused = true
            var mappedEvent = event
            mappedEvent.y = mappedEvent.y - 72
            browserView.pointerMotion(window: window, event: mappedEvent)
        }
    }

    private func pointerButtonCallback (window: WaylandWSIWindow, event: InputPointerEvent) {
        if event.y <= 72 {
            _browserFocused = false
            uiView.pointerButton(window: window, event: event)
        } else {
            _browserFocused = true
            var mappedEvent = event
            mappedEvent.y = mappedEvent.y - 72
            browserView.pointerButton(window: window, event: mappedEvent)
        }
    }

    private func pointerAxisCallback (window: WaylandWSIWindow, event: InputAxisEvent) {
        if event.y <= 72 {
            _browserFocused = false
            uiView.pointerAxis(window: window, event: event)
        } else {
            _browserFocused = true
            var mappedEvent = event
            mappedEvent.y = mappedEvent.y - 72
            browserView.pointerAxis(window: window, event: mappedEvent)
        }
    }
    */
    private func keyboardButtonCallback (window: WaylandWSIWindow, event: InputKeyboardEvent) {
        DispatchQueue.main.async {
            self.process(key: event)
        }
    }

    private func process (key event: InputKeyboardEvent) {
        // Intercept globals
        switch Int32(event.keyCode) {
        case XKB_KEY_o:
            if event.pressed && event.modifiers == InputModifier.control {
                //self.showOpenDialog()
            }
        case XKB_KEY_c:
            if event.pressed && event.modifiers == InputModifier.control {
                exit(0)
            }
        default:
            Log.debug("Unhandled: \(String(describing: event))")
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

    func loadUI() {
        _view.load(html: "<html><body>Hi</body></html>")
        return
//      guard let loaderPath = URL(string: "imprint://imprint/index.html") else {
        guard let loaderPath = URL(string: "http://127.0.0.1:9000/index.html") else {
            Log.error("Unable to create UI path")
            return
        }
        Log.info("Loading UI from \(loaderPath)")
        _view.load(url: loaderPath)
    }

        func load(html: String) {
            _view.load(html: html)
        }

    func handleUI(request: String) -> (mimeType: String, data: Data)? {
        Log.verbose("Got request for \(request)")

        let uiRequestURL = URL(fileURLWithPath: SettingsController.shared.ui.path)
                .appendingPathComponent(request)
        Log.verbose("Attempting load from \(uiRequestURL)")
        let pathExtension = uiRequestURL.pathExtension
        let mimeType = MimeTypes[pathExtension] ?? "application/octet-stream"
        Log.verbose("Got \(mimeType) for \(pathExtension)")

        let uiData: Data
        do {
            uiData = try Data(contentsOf: uiRequestURL)
        } catch let error {
            Log.error("Load failed for \(uiRequestURL): \(error.localizedDescription)")
            return nil
        }
        Log.verbose("Loaded \(uiData.count) bytes from \(uiRequestURL)")
        return (mimeType: mimeType, data: uiData)
    }

    func handleMail(request: String, parameters: [URLQueryItem]?) -> (mimeType: String, data: Data)? {

        return nil
        /*guard let dataSource = dataSource else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json: Data
        switch request {
        case "mailboxes":
            let data = dataSource.mailboxes()
            do {
                json = try encoder.encode(data)
            } catch let error {
                Log.error(error.localizedDescription)
                return nil
            }
        case "conversations":
            do {
                let mailbox = try dataSource.inbox()
                let data = dataSource.conversations(for: mailbox)
                json = try encoder.encode(data)
            } catch let error {
                Log.error(error.localizedDescription)
                return nil
            }
        default:
            Log.warning("Unknown mail request type \(request)")
            return nil
        }
        return ("application/json", json)*/
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
    if pathComponents[0] == "data" {
        request = pathComponents[1...].joined(separator: "/")
        response = controller.handleMail(request: request, parameters: components.queryItems)
    } else {
        request = pathComponents[1...].joined(separator: "/")
        response = controller.handleUI(request: request)
    }
    completion(response?.mimeType, response?.data)
}
