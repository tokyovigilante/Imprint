#if os(Linux)

import CWebKitWPE
import CWebKitWPEFDO
import Foundation
import Harness
import LoggerAPI

class WebViewImage {
    let id: UUID
    let viewID: UUID
    let image: OpaquePointer
    let time: PrecisionTimer
    weak var backend: WPEViewBackend?

    init (viewID: UUID, image: OpaquePointer, time: PrecisionTimer, backend: WPEViewBackend) {
        self.id = UUID()
        self.viewID = viewID
        self.image = image
        self.time = time
        self.backend = backend
    }
}

class WPEViewBackend {

    let id: UUID

    fileprivate var _exportable: OpaquePointer! = nil
    private var _backend: OpaquePointer! = nil
    private var _viewBackend: OpaquePointer! = nil

    internal var backend: OpaquePointer {
        return _backend
    }
    internal var viewBackend: OpaquePointer {
        return _viewBackend
    }

    private let _client = UnsafeMutablePointer<wpe_view_backend_exportable_fdo_egl_client>.allocate(capacity: 1)

    var exportImageCallback: ((WebViewImage) -> Void)? = nil
    fileprivate var _inflightImages: [UUID: WebViewImage] = [:]

    init? () {
        id = UUID()

        _client.pointee.export_fdo_egl_image = exportImage
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let exportable = wpe_view_backend_exportable_fdo_egl_create(_client,
                unsafeSelf, 640, 480) else {
            Log.error("WPE FDO exportable creation failed")
            return nil
        }
        _exportable = exportable

        /* init WPE view backend */
        guard let backend = wpe_view_backend_exportable_fdo_get_view_backend(_exportable) else {
            Log.error("WPE FDO backend creation failed")
            return nil
        }
        _backend = backend

        guard let viewBackend = webkit_web_view_backend_new(_backend, nil,
                /*unsafeBitCast(*/
                    //wpe_view_backend_exportable_fdo_destroy,
                    /*to: GDestroyNotify.self),*/
                UnsafeMutableRawPointer(_exportable)) else {
            Log.error("WebKit view creation failed")
            return nil
        }
        _viewBackend = viewBackend

        Log.info("Initialised WPE WebKit view backend")
    }

    func setView (width: UInt32, height: UInt32) {
        wpe_view_backend_dispatch_set_size(_backend, width, height)
    }

    func setView (scale: Float) {
        wpe_view_backend_dispatch_set_device_scale_factor(_backend, scale)
    }

    func signalFrameComplete () {
        wpe_view_backend_exportable_fdo_dispatch_frame_complete(_exportable)
    }

    func release (image: WebViewImage) {
        if let _ = _inflightImages.removeValue(forKey: image.id) {
            wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(_exportable,
                    image.image)
        } else {
            Log.error("Frame \(image.id) not associated with view \(id)")
        }
    }

    deinit {
        _client.deallocate()
    }
}

fileprivate var exportImage: @convention(c) (UnsafeMutableRawPointer?,
        OpaquePointer?) -> Void = { (data, exported) in
    guard let data = data, let exported = exported else {
        Log.error("Invalid export_fdo_egl_image callback data")
        return
    }
    let backend = Unmanaged<WPEViewBackend>.fromOpaque(data)
            .takeUnretainedValue()
    let image = WebViewImage(
            viewID: backend.id,
            image: exported,
            time: PrecisionTimer(),
            backend: backend)
    /*Log.debug("""
            WebViewImage \(image.id) at \(String(format: "%0.02f", image.time.startTime)) \
            for \(image.viewID)
            """)*/
    backend._inflightImages[image.id] = image

    if let exportImageCallback = backend.exportImageCallback {
        exportImageCallback(image)
    } else {
        Log.warning("viewBackend.exportFrameCallback not set, eating frame")
        //TODO: dispatch after ?
        backend.signalFrameComplete()
        backend.release(image: image)
    }
}

#endif
