#if os(Linux)

import CEGL
import CWaylandEGL
import CWebKitWPE
import Foundation
import Harness
import LoggerAPI

protocol ScriptMessageDelegate: class {

    func callback (result: OpaquePointer)
}

class WPEView {

    var uuid: UUID {
        return _backend.id
    }

    var loadProgress: Double {
        return webkit_web_view_get_estimated_load_progress(_view)
    }

    var title: String {
        return String(cString: webkit_web_view_get_title(_view), encoding: .utf8) ?? ""
    }

    var uri: String {
        return String(cString: webkit_web_view_get_uri(_view), encoding: .utf8) ?? ""
    }

    var loadProgressCallback: ((WPEView, Double) -> Void)? = nil
    var uriChangedCallback: ((WPEView, String) -> Void)? = nil
    var titleCallback: ((WPEView, String) -> Void)? = nil

    var userContentManager: UnsafeMutablePointer<WebKitUserContentManager> {
        return webkit_web_view_get_user_content_manager(_view)
    }

    private let _backend: WPEViewBackend
    private let _view: UnsafeMutablePointer<WebKitWebView>

    var scaleFactor: Double = 1.0 {
        didSet {
            _backend.setView(scale: Float(scaleFactor))
        }
    }

    var frameUpdateCallback: ((WebViewImage) -> Void)? = nil

    init? (context: WPEContext) {

        guard let backend = WPEViewBackend() else {
            Log.error("WebKit WPE backend creation failed")
            return nil
        }
        _backend = backend

        guard let view = webkit_web_view_new_with_context(_backend.viewBackend,
                context._context) else {
            Log.error("WebKit view creation failed")
            return nil
        }
        _view = view

        let settings = webkit_web_view_get_settings(_view)
        let enableInspector: Bool
        if let server = ProcessInfo.processInfo.environment[
                "WEBKIT_INSPECTOR_SERVER"] {
            Log.debug("Enabling debug server at \(server)")
            enableInspector = true
        } else {
            enableInspector = false
        }
        webkit_settings_set_enable_developer_extras(settings, enableInspector ? 1 : 0)
        webkit_settings_set_enable_webgl(settings, 1)
        webkit_web_view_set_settings(_view, settings)

        var transparent =
                WebKitColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        webkit_web_view_set_background_color(view, &transparent)

        _backend.exportImageCallback = exportImageCallback

        connectErrorHandlers()
        connectProgressHandlers()
        connectActionHandlers()
    }

    func setView (width: UInt32, height: UInt32) {
        _backend.setView(width: width, height: height)
    }

    func pointerMotion (event: InputPointerEvent) {

        var wpeEvent = wpe_input_pointer_event(
            type: wpe_input_pointer_event_type_motion,
            time: UInt32(event.time),
            x: Int32(event.x * scaleFactor),
            y: Int32(event.y * scaleFactor),
            button: UInt32(event.button),
            state: UInt32(event.state),
            modifiers: event.modifiers.rawValue)
        wpe_view_backend_dispatch_pointer_event(_backend.backend, &wpeEvent)
    }

    func pointerButton (event: InputPointerEvent) {

        var wpeEvent = wpe_input_pointer_event(
            type: wpe_input_pointer_event_type_button,
            time: UInt32(event.time),
            x: Int32(event.x * scaleFactor),
            y: Int32(event.y * scaleFactor),
            button: UInt32(event.button),
            state: UInt32(event.state),
            modifiers: event.modifiers.rawValue
        )
        wpe_view_backend_dispatch_pointer_event(self._backend.backend, &wpeEvent)
    }

    func pointerAxis (event: InputAxisEvent) {

        var wpeEvent = wpe_input_axis_event(
                type: wpe_input_axis_event_type_motion,
                time: UInt32(event.time),
                x: Int32(event.x * scaleFactor),
                y: Int32(event.y * scaleFactor),
                axis: event.axis.waylandValue,
                value: Int32(event.value),
                modifiers: event.modifiers.rawValue
            )
        wpe_view_backend_dispatch_axis_event(_backend.backend, &wpeEvent)
    }

    func keyButton (event: InputKeyboardEvent) {

        var wpeEvent = wpe_input_keyboard_event(
            time: event.time,
            key_code: event.keyCode,
            hardware_key_code: event.hardwareKeyCode,
            pressed: event.pressed,
            modifiers: event.modifiers.rawValue
        )

        wpe_view_backend_dispatch_keyboard_event(self._backend.backend, &wpeEvent)
    }

    private func exportImageCallback(image: WebViewImage) {

        if let frameUpdateCallback = frameUpdateCallback {
            frameUpdateCallback(image)
        } else {
            Log.warning("WPEView.frameUpdateCallback not set")
            _backend.signalFrameComplete()
        }
    }

    private func connectErrorHandlers () {
        connect(signal: "load_failed", callback: unsafeBitCast(handleWebViewLoadFailed, to: GCallback.self))
        connect(signal: "load-failed-with-tls-errors", callback: unsafeBitCast(handleWebViewLoadFailedTLS, to: GCallback.self))
        connect(signal: "web-process-terminated", callback: unsafeBitCast(handleWebProcessTerminated, to: GCallback.self))

    }

    private func connectProgressHandlers () {
        connect(signal: "load_changed", callback: unsafeBitCast(handleWebViewLoadChanged, to: GCallback.self))
        connect(signal: "notify::estimated-load-progress", callback: unsafeBitCast(updateLoadProgress, to: GCallback.self))
        connect(signal: "notify::title", callback: unsafeBitCast(updateTitle, to: GCallback.self))
    }

    private func connectActionHandlers () {
        //connect(signal: "create", callback: unsafeBitCast(createView, to: GCallback.self))
        //connect(signal: "decide-policy", callback: unsafeBitCast(decidePolicy, to: GCallback.self))
    }

    private func connect (signal: String, callback: @escaping GCallback) {
        g_signal_connect_data(_view, signal, callback,
                gpointer(Unmanaged.passUnretained(self).toOpaque()),
                nil, GConnectFlags(rawValue: 0))
    }

    public func load (url: URL) {
        let uri = url.absoluteString.cString(using: .utf8)
        webkit_web_view_load_uri(_view, uri)
    }

    public func load (html string: String) {
        webkit_web_view_load_html(_view, string.cString(using: .utf8), nil)
    }

    public func registerScriptHandler (name: String, delegate: ScriptMessageDelegate) -> Bool {

        g_signal_connect_data(userContentManager, "script-message-received::\(name)",
                unsafeBitCast(scriptMessageRecievedCallback, to: GCallback.self),
                gpointer(Unmanaged.passUnretained(delegate as AnyObject).toOpaque()),
                nil, GConnectFlags(rawValue: 0))

        let success = webkit_user_content_manager_register_script_message_handler(userContentManager, name) != 0
        if !success {
            Log.error("Failed to register WebExtension script handler")
        }
        return success
    }

    public func add (script scriptString: String, frames: WebKitUserContentInjectedFrames,
            time: WebKitUserScriptInjectionTime, whitelist: [String] = [],
            blacklist: [URL] = []) {
        let script = webkit_user_script_new(scriptString, frames, time, nil, nil)
        webkit_user_content_manager_add_script(userContentManager, script)
    }

    public func run (script: String) {
        Log.debug(script)
        webkit_web_view_run_javascript(_view, script, nil,
                unsafeBitCast(scriptRunCallback, to: GAsyncReadyCallback.self), nil)
    }
}

fileprivate var scriptMessageRecievedCallback: @convention(c)
        (UnsafeMutablePointer<WebKitUserContentManager>,
        OpaquePointer/*WebKitJavascriptResult*/, UnsafeMutableRawPointer) -> Void =
        { manager, result, data in
    let delegate = Unmanaged<AnyObject>.fromOpaque(data).takeUnretainedValue() as! ScriptMessageDelegate
    delegate.callback(result: result)
}

fileprivate var scriptRunCallback: @convention(c) () -> Void = {
    Log.debug("Script done")
}

fileprivate var destroyCallback: @convention(c)
        (UnsafeMutableRawPointer?) -> Void = { data in
    data?.deallocate()
}

fileprivate let handleWebViewLoadFailed: @convention(c) (WebKitWebView,
        WebKitLoadEvent, UnsafeMutablePointer<Int8>,
        UnsafeMutablePointer<GError>) -> Void = { view, loadEvent, failingURI, error in
    Log.error("load failed")
}

fileprivate var handleWebViewLoadFailedTLS: @convention(c) (WebKitWebView,
        WebKitLoadEvent, UnsafeMutablePointer<GTlsCertificate>, UInt32)
        -> Void = { view, loadEvent, certificate, flags in
    var messages = [String]()
    if flags & G_TLS_CERTIFICATE_UNKNOWN_CA.rawValue != 0 {
        messages.append("The signing certificate authority is not known.")
    }
    if flags & G_TLS_CERTIFICATE_BAD_IDENTITY.rawValue != 0 {
        messages.append("The certificate does not match the expected identity of the site that it was retrieved from.")
    }
    if flags & G_TLS_CERTIFICATE_NOT_ACTIVATED.rawValue != 0 {
        messages.append("The certificate's activation time is still in the future")
    }
    if flags & G_TLS_CERTIFICATE_EXPIRED.rawValue != 0 {
        messages.append("The certificate has expired.")
    }
    if flags & G_TLS_CERTIFICATE_REVOKED.rawValue != 0 {
        messages.append("The certificate has been revoked according to the GTlsConnection's certificate revocation list.")
    }
    if flags & G_TLS_CERTIFICATE_INSECURE.rawValue != 0 {
        messages.append("The certificate's algorithm is considered insecure.")
    }
    if flags & G_TLS_CERTIFICATE_GENERIC_ERROR.rawValue != 0 {
        messages.append("Some other error occurred validating the certificate.")
    }
    if messages.isEmpty {
        messages.append("Unknown failure reason")
    }
    Log.error("TLS load failed: \(messages)")
}

fileprivate let handleWebProcessTerminated: @convention(c) (WebKitWebView, WebKitLoadEvent, UnsafeMutablePointer<Int8>, UnsafeMutablePointer<GError>) -> Void = { view, event, failingURI, error in
    Log.error("web process terminated")
}

fileprivate let handleWebViewLoadChanged: @convention(c)
        (UnsafeMutableRawPointer, WebKitLoadEvent, UnsafeMutableRawPointer)
        -> Void = { wpeView, loadEvent, data in
    switch loadEvent {
    case WEBKIT_LOAD_STARTED,
            WEBKIT_LOAD_REDIRECTED,
            WEBKIT_LOAD_COMMITTED:
        let view = Unmanaged<WPEView>.fromOpaque(data)
                .takeUnretainedValue()
        let uri = view.uri
        Log.debug(uri)
        view.uriChangedCallback?(view, uri)
    case WEBKIT_LOAD_FINISHED:
        Log.debug("load finished")
    default:
        Log.warning("Unknown load event \(loadEvent)")
    }
}

fileprivate let updateLoadProgress: @convention(c)
        (UnsafeMutableRawPointer, UnsafeMutablePointer<GParamSpec>, UnsafeMutableRawPointer)
        -> Void = { object, paramSpec, data in
    let view = Unmanaged<WPEView>.fromOpaque(data)
            .takeUnretainedValue()
    let progress = view.loadProgress
    Log.debug("Load \(String(format: "%.0f", progress * 100))%")
    view.loadProgressCallback?(view, progress)
}

fileprivate let updateTitle: @convention(c)
        (UnsafeMutableRawPointer, UnsafeMutablePointer<GParamSpec>, UnsafeMutableRawPointer)
        -> Void = { object, paramSpec, data in
    let view = Unmanaged<WPEView>.fromOpaque(data)
            .takeUnretainedValue()
    let title = view.title
    Log.debug("Title changed to \(title)")
    view.titleCallback?(view, title)
}
/*
fileprivate let createView: @convention(c)
        (WebKitWebView, WebKitNavigationAction, UnsafeMutableRawPointer)
        -> Void = { view, action, data in
    Log.info("New view requested")
}

fileprivate let decidePolicy: @convention(c)
        (WebKitWebView, WebKitPolicyDecision, WebKitPolicyDecisionType, UnsafeMutableRawPointer)
        -> Bool = { view, decision, decisionType, data in
    Log.info("Policy decision request")

}*/

#endif
