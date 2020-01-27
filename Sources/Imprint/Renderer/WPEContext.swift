#if os(Linux)
import Airframe
import CWebKitWPE
import CWebKitWPEFDO
import Foundation
import LoggerAPI

public typealias URIHandler = @convention(c) (UnsafeMutableRawPointer, URL, ((String?, Data?) -> Void)) -> Void

fileprivate struct URIHandlerData {
    var object: UnsafeMutableRawPointer
    var callback: URIHandler
}

class WPEContext {

    internal let _context: UnsafeMutablePointer<WebKitWebContext>

    fileprivate var _schemeHandlers = [String: URIHandlerData]()

    init? (window: WaylandWSIWindow, debug: Bool = false) {

        if !wpe_loader_init("libWPEBackend-fdo-1.0.so") {
            Log.error("WPE Loader initialise failed")
            return nil
        }

        if !wpe_fdo_initialize_for_egl_display(window.eglDisplay) {
            Log.error("WPE FDO backend initialise failed")
            return nil
        }

        if debug {
            setenv("WEBKIT_INSPECTOR_SERVER".utf8String!, "127.0.0.1:1234".utf8String!, 1)
        }

        guard let context = webkit_web_context_new_ephemeral() else {
            Log.error("WebKit context creation failed")
            return nil
        }
        _context = context

        webkit_web_context_set_process_model (_context, WEBKIT_PROCESS_MODEL_MULTIPLE_SECONDARY_PROCESSES)

        webkit_web_context_set_tls_errors_policy(_context,
                WEBKIT_TLS_ERRORS_POLICY_IGNORE)
    }

    private func signalConnect (signal: String, callback: @escaping GCallback) {
        g_signal_connect_data(_context, signal, callback,
                gpointer(Unmanaged.passUnretained(self).toOpaque()),
                nil, GConnectFlags(rawValue: 0))
    }

    func connectURIHandler (for scheme: String, data: UnsafeMutableRawPointer, callback: @escaping URIHandler) {

        _schemeHandlers[scheme] = URIHandlerData(object: data, callback: callback)
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()

        webkit_web_context_register_uri_scheme(_context, scheme,
                uriSchemeHandlerCallback, unsafeSelf, nil)
        let manager = webkit_web_context_get_security_manager(_context)
        webkit_security_manager_register_uri_scheme_as_cors_enabled(manager, scheme)
    }

}

fileprivate var destroyCallback: @convention(c)
        (UnsafeMutableRawPointer?) -> Void = { data in
    data?.deallocate()
}

fileprivate var uriSchemeHandlerCallback: @convention(c)
        (UnsafeMutablePointer<WebKitURISchemeRequest>?, UnsafeMutableRawPointer?)
         -> Void = { request, data in
    guard let data = data else {
        return
    }
    let context = Unmanaged<WPEContext>.fromOpaque(data).takeUnretainedValue()

    guard let uriString = String(cString: webkit_uri_scheme_request_get_uri(request),
            encoding: .utf8),
            let uri = URL(string: uriString),
            let scheme = uri.scheme else {
        Log.error("Invalid URI from WebKit")
        var error = GError()
        webkit_uri_scheme_request_finish_error(request, &error)
        return
    }

    guard let handler = context._schemeHandlers[scheme] else {
        Log.error("No handler for scheme")
        var error = GError()
        webkit_uri_scheme_request_finish_error(request, &error)
        return
    }

    handler.callback(handler.object, uri) { mimeType, data in
        if let mimeType = mimeType, let data = data {
            var dataPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: dataPointer, count: data.count)
            let stream = g_memory_input_stream_new_from_data(dataPointer,
                    data.count, destroyCallback)
            webkit_uri_scheme_request_finish(request, stream, data.count, mimeType)
            g_object_unref(stream)
        } else {
            var error = GError()
            webkit_uri_scheme_request_finish_error(request, &error)
        }
    }
}

#endif
