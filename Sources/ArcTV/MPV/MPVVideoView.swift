import AppKit
import Libmpv
import OpenGL.GL
import OpenGL.GL3

/// Events the video view reports to the player model (always delivered on the main thread).
enum MPVEvent {
    case position(Double)
    case duration(Double)
    case paused(Bool)
    case buffering(Bool)
    case ended
    case failed(String)
}

/// A view that shows an mpv video. Adapted from the MPVKit macOS demo (OpenGL): mpv draws each frame into this view's OpenGL context.
final class MPVVideoView: NSOpenGLView {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private let queue = DispatchQueue(label: "tv.arc.mac.mpv", qos: .userInteractive)
    private var defaultFBO: GLint = -1
    var onEvent: ((MPVEvent) -> Void)?

    override class func defaultPixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADepthSize), NSOpenGLPixelFormatAttribute(24),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAStencilSize), NSOpenGLPixelFormatAttribute(8),
            NSOpenGLPixelFormatAttribute(0)
        ]
        return NSOpenGLPixelFormat(attributes: attributes)!
    }

    /// Makes the OpenGL context ready and starts mpv.
    func start(url: URL, startAt: Double = 0) {
        wantsBestResolutionOpenGLSurface = true
        autoresizingMask = [.width, .height]
        openGLContext?.makeCurrentContext()
        setupMpv(startAt: startAt)
        command("loadfile", args: [url.absoluteString, "replace"])
    }

    private func setupMpv(startAt: Double) {
        guard let handle = mpv_create() else {
            onEvent?(.failed("The player could not be started."))
            return
        }
        mpv = handle
        _ = mpv_request_log_messages(handle, "no")
        _ = mpv_set_option_string(handle, "subs-match-os-language", "yes")
        _ = mpv_set_option_string(handle, "subs-fallback", "yes")
        _ = mpv_set_option_string(handle, "hwdec", "auto-safe")
        _ = mpv_set_option_string(handle, "vo", "libmpv")
        _ = mpv_set_option_string(handle, "ytdl", "no")
        _ = mpv_set_option_string(handle, "keep-open", "no")
        if startAt > 1 { _ = mpv_set_option_string(handle, "start", String(Int(startAt))) }
        guard mpv_initialize(handle) >= 0 else {
            onEvent?(.failed("The player could not be started."))
            return
        }

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { (ctx, name) in MPVVideoView.getProcAddress(ctx, name) },
            get_proc_address_ctx: nil
        )
        var created: OpaquePointer?
        let result = withUnsafeMutablePointer(to: &initParams) { initPointer -> Int32 in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPointer),
                mpv_render_param()
            ]
            return mpv_render_context_create(&created, handle, &params)
        }
        guard result >= 0, let context = created else {
            onEvent?(.failed("The video output could not be started."))
            return
        }
        renderContext = context
        mpv_render_context_set_update_callback(context, mpvGLUpdate, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(handle, mpvWakeUp, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    // MARK: Controls

    func command(_ name: String, args: [String] = []) {
        guard let handle = mpv else { return }
        var pointers: [UnsafeMutablePointer<CChar>?] = ([name] + args).map { strdup($0) }
        pointers.append(nil)
        defer { for pointer in pointers { free(pointer) } }
        var constPointers: [UnsafePointer<CChar>?] = pointers.map { $0.map { UnsafePointer($0) } }
        _ = mpv_command(handle, &constPointers)
    }

    func setFlag(_ name: String, _ value: Bool) {
        guard let handle = mpv else { return }
        var data: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &data)
    }

    func setString(_ name: String, _ value: String) {
        guard let handle = mpv else { return }
        mpv_set_property_string(handle, name, value)
    }

    func string(_ name: String) -> String? {
        guard let handle = mpv, let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func seek(to seconds: Double) { command("seek", args: [String(seconds), "absolute"]) }

    func seek(by seconds: Double) { command("seek", args: [String(seconds), "relative"]) }

    /// Stops mpv and frees everything it holds. Safe to call more than once.
    func shutdown() {
        queue.sync {
            guard let handle = mpv else { return }
            mpv_set_wakeup_callback(handle, nil, nil)
            openGLContext?.makeCurrentContext()
            if let context = renderContext {
                mpv_render_context_set_update_callback(context, nil, nil)
                mpv_render_context_free(context)
                renderContext = nil
            }
            mpv_terminate_destroy(handle)
            mpv = nil
        }
    }

    // MARK: Events

    fileprivate func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let handle = self.mpv {
                guard let event = mpv_wait_event(handle, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE { break }
                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    guard let raw = event.pointee.data else { continue }
                    let property = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
                    let name = String(cString: property.name)
                    guard let data = property.data else { continue }
                    switch name {
                    case "time-pos":
                        self.emit(.position(data.assumingMemoryBound(to: Double.self).pointee))
                    case "duration":
                        self.emit(.duration(data.assumingMemoryBound(to: Double.self).pointee))
                    case "pause":
                        self.emit(.paused(data.assumingMemoryBound(to: Int32.self).pointee != 0))
                    case "paused-for-cache":
                        self.emit(.buffering(data.assumingMemoryBound(to: Int32.self).pointee != 0))
                    default:
                        break
                    }
                case MPV_EVENT_END_FILE:
                    guard let raw = event.pointee.data else { continue }
                    let ending = raw.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if ending.reason == MPV_END_FILE_REASON_ERROR {
                        self.emit(.failed(String(cString: mpv_error_string(ending.error))))
                    } else if ending.reason == MPV_END_FILE_REASON_EOF {
                        self.emit(.ended)
                    }
                default:
                    break
                }
            }
        }
    }

    private func emit(_ event: MPVEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = renderContext else { return }

        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))

        glGetIntegerv(UInt32(GL_FRAMEBUFFER_BINDING), &defaultFBO)
        var dims: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &dims)

        var fbo = mpv_opengl_fbo(fbo: Int32(defaultFBO), w: Int32(dims[2]), h: Int32(dims[3]), internal_format: 0)
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &flip) { flipPointer in
            withUnsafeMutablePointer(to: &fbo) { fboPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPointer),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPointer),
                    mpv_render_param()
                ]
                mpv_render_context_render(context, &params)
            }
        }
        openGLContext?.flushBuffer()
    }

    private static func getProcAddress(_: UnsafeMutableRawPointer?, _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
        let identifier = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
        return CFBundleGetFunctionPointerForName(identifier, symbolName)
    }

    deinit {
        shutdown()
    }
}

private func mpvGLUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPVVideoView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { view.display() }
}

private func mpvWakeUp(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPVVideoView>.fromOpaque(context).takeUnretainedValue()
    view.readEvents()
}
