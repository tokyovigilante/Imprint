import Airframe
import Foundation
import LoggerAPI
#if os(Linux)
import CWaylandEGL
import CWebKitWPEFDO
import WaylandShims
#endif

class RenderManager {

    private let _window: AirframeWindow

    init? (window: AirframeWindow) {
        _window = window
    }

    func updateUI (image: WebViewImage) {
        Log.debug("""
                Updating UI from frame \(image.id)at \(String(format: "%0.02f",
                image.time.startTime)) for view \(image.viewID)
                """)
        guard let waylandWindow = _window as? WaylandWSIWindow else {
            Log.error("Invalid WSI window type")
            return
        }
        let surface = waylandWindow.wlSurface
        update(surface: surface, image: image)
    }

    private func update(surface: OpaquePointer, image: WebViewImage) {
        guard let waylandWindow = _window as? WaylandWSIWindow else {
            Log.error("Invalid WSI window type")
            return
        }
        guard let eglImage = OpaquePointer(wpe_fdo_egl_exported_image_get_egl_image(image.image)) else {
            Log.error("Invalid image data")
            return
        }
        guard let buffer = OpaquePointer(
                shim_create_wlbuffer_from_image(
                waylandWindow.eglDisplay, UnsafeMutableRawPointer(eglImage)
                )) else {
            Log.error("wl_buffer creation from wl_resource failed")
            return
        }
        let unsafeImage = Unmanaged.passUnretained(image).toOpaque()
        wl_buffer_add_listener(buffer, &bufferListener, unsafeImage)

        wl_surface_attach(surface, buffer, 0, 0)

        let pixelWidth = Int32(Double(wpe_fdo_egl_exported_image_get_width(image.image)) * _window.scaleFactor)
        let pixelHeight = Int32(Double(wpe_fdo_egl_exported_image_get_height(image.image)) * _window.scaleFactor)
        wl_surface_damage_buffer(surface, 0, 0, pixelWidth, pixelHeight)

        let callback = wl_surface_frame(surface)
        if wl_callback_add_listener(callback, &frameListener, unsafeImage)
                != 0 {
            Log.error("wl_callback_add_listener failed")
        }
        wl_surface_commit(surface)
    }
}

fileprivate var onSurfaceFrame: @convention(c) (UnsafeMutableRawPointer?,
        OpaquePointer?, UInt32) -> Void = { data, callback, time in
    wl_callback_destroy(callback)
    guard let data = data else {
        Log.error("Invalid onSurfaceFrame callback data")
        return
    }
    let frame = Unmanaged<WebViewImage>.fromOpaque(data)
            .takeUnretainedValue()
    frame.backend?.signalFrameComplete()
}

fileprivate var frameListener = wl_callback_listener(
    done: onSurfaceFrame
)

fileprivate var onBufferRelease: @convention(c) (UnsafeMutableRawPointer?,
        OpaquePointer?) -> Void = { data, buffer in
    defer {
        wl_buffer_destroy(buffer)
    }
    guard let data = data else {
        Log.error("Invalid onSurfaceFrame callback data")
        return
    }
    let image = Unmanaged<WebViewImage>.fromOpaque(data)
            .takeUnretainedValue()
    image.backend?.release(image: image)
}

fileprivate var bufferListener = wl_buffer_listener(
    release: onBufferRelease
)
