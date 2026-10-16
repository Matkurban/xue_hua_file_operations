import AVFoundation
import Cocoa
import FlutterMacOS

/// Takes a photo or records a video with AVFoundation. A sheet (or a
/// standalone panel when the app has no window) shows the camera preview with
/// "Take Photo" / "Record" / "Stop" / "Cancel" buttons.
final class CameraCapture: NSObject, AVCapturePhotoCaptureDelegate,
    AVCaptureFileOutputRecordingDelegate, NSWindowDelegate
{
    private struct Request {
        let isVideo: Bool
        let preferFront: Bool
        let maxDurationSeconds: Int?
        let maxWidth: Double?
        let maxHeight: Double?
        let imageQuality: Int?
        let withData: Bool
    }

    private var request: Request?
    private var pendingResult: FlutterResult?
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var panel: NSPanel?
    private var parentWindow: NSWindow?
    private var primaryButton: NSButton?
    private var stopButton: NSButton?
    private var recordingURL: URL?
    private var cancelRequested = false
    private let sessionQueue = DispatchQueue(label: "xue_hua_file_operations.camera")

    /// `true` while a camera session is on screen.
    var isBusy: Bool { pendingResult != nil }

    // MARK: - Entry point

    func capture(call: FlutterMethodCall, result: @escaping FlutterResult, isVideo: Bool) {
        let args = call.arguments as? [String: Any]
        let request = Request(
            isVideo: isVideo,
            preferFront: (args?["preferredCamera"] as? String) == "front",
            maxDurationSeconds: (args?["maxDurationSeconds"] as? NSNumber)?.intValue,
            maxWidth: (args?["maxWidth"] as? NSNumber)?.doubleValue,
            maxHeight: (args?["maxHeight"] as? NSNumber)?.doubleValue,
            imageQuality: (args?["imageQuality"] as? NSNumber)?.intValue,
            withData: args?["withData"] as? Bool ?? false
        )

        guard pendingResult == nil else {
            result(FlutterError(
                code: "invalid_args",
                message: "Another file operation is in progress",
                details: nil
            ))
            return
        }

        // Without these keys macOS terminates the app when the camera opens.
        let info = Bundle.main.infoDictionary
        if info?["NSCameraUsageDescription"] == nil {
            result(FlutterError(
                code: "invalid_args",
                message: "NSCameraUsageDescription is missing from Info.plist",
                details: nil
            ))
            return
        }
        if isVideo, info?["NSMicrophoneUsageDescription"] == nil {
            result(FlutterError(
                code: "invalid_args",
                message: "NSMicrophoneUsageDescription is missing from Info.plist",
                details: nil
            ))
            return
        }

        self.request = request
        pendingResult = result

        requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.finish(FlutterError(
                    code: "permission_denied",
                    message: "The user did not allow camera access.",
                    details: nil
                ))
                return
            }
            if isVideo {
                // Microphone is optional: without it the video has no sound.
                self.requestAccess(for: .audio) { [weak self] audioGranted in
                    self?.startSession(withAudio: audioGranted)
                }
            } else {
                self.startSession(withAudio: false)
            }
        }
    }

    private func requestAccess(for type: AVMediaType, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    // MARK: - Device selection

    /// Built-in (FaceTime) camera first for `preferFront`, an external camera
    /// first otherwise. Falls back to whatever camera exists.
    private func pickDevice(preferFront: Bool) -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
        } else {
            types.append(.externalUnknown)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        let builtIn = devices.filter { $0.deviceType == .builtInWideAngleCamera }
        let external = devices.filter { $0.deviceType != .builtInWideAngleCamera }
        let ordered = preferFront ? builtIn + external : external + builtIn
        return ordered.first ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Session

    private func startSession(withAudio: Bool) {
        guard let request = request else { return }
        guard let device = pickDevice(preferFront: request.preferFront) else {
            finish(FlutterError(
                code: "unsupported",
                message: "No camera was found on this Mac",
                details: nil
            ))
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CaptureError.configuration("Unable to use the camera input")
            }
            session.addInput(input)

            if request.isVideo {
                if withAudio, let mic = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(audioInput)
                {
                    session.addInput(audioInput)
                }
                let movie = AVCaptureMovieFileOutput()
                guard session.canAddOutput(movie) else {
                    throw CaptureError.configuration("Unable to record video")
                }
                session.addOutput(movie)
                if let seconds = request.maxDurationSeconds, seconds > 0 {
                    movie.maxRecordedDuration = CMTime(seconds: Double(seconds), preferredTimescale: 600)
                }
                movieOutput = movie
            } else {
                let photo = AVCapturePhotoOutput()
                guard session.canAddOutput(photo) else {
                    throw CaptureError.configuration("Unable to capture photos")
                }
                session.addOutput(photo)
                photoOutput = photo
            }
        } catch {
            session.commitConfiguration()
            finish(FlutterError(
                code: "io_error",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }
        session.commitConfiguration()
        self.session = session

        showPanel(session: session)
        sessionQueue.async { session.startRunning() }
        scheduleTestAutomation()
    }

    // MARK: - Test hook

    /// Test hook for UI tests (flutter_driver cannot reach the native
    /// sheet): when the process environment has `XUE_HUA_CAMERA_TEST_AUTO=1`
    /// the "Take Photo" / "Record" button is pressed ~1.5 s after the preview
    /// starts and a recording is stopped ~2 s later. The real camera is still
    /// used. Without the variable nothing happens.
    private func scheduleTestAutomation() {
        guard ProcessInfo.processInfo.environment["XUE_HUA_CAMERA_TEST_AUTO"] == "1" else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.pendingResult != nil else { return }
            self.primaryTapped()
            guard self.request?.isVideo == true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.movieOutput?.isRecording == true else { return }
                self.stopTapped()
            }
        }
    }

    // MARK: - UI

    private func showPanel(session: AVCaptureSession) {
        guard let request = request else { return }
        let size = NSSize(width: 640, height: 520)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = request.isVideo ? "Record Video" : "Take Photo"
        panel.delegate = self
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true

        let preview = NSView(frame: NSRect(x: 0, y: 48, width: size.width, height: size.height - 48))
        preview.wantsLayer = true
        preview.autoresizingMask = [.width, .height]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = preview.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        preview.layer?.addSublayer(layer)
        preview.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(preview)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.frame = NSRect(x: 16, y: 10, width: 100, height: 28)
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)

        let primary = NSButton(
            title: request.isVideo ? "Record" : "Take Photo",
            target: self,
            action: #selector(primaryTapped)
        )
        primary.frame = NSRect(x: size.width - 136, y: 10, width: 120, height: 28)
        primary.keyEquivalent = "\r"
        content.addSubview(primary)
        primaryButton = primary

        if request.isVideo {
            let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
            stop.frame = primary.frame
            stop.isHidden = true
            content.addSubview(stop)
            stopButton = stop
        }

        panel.contentView = content
        self.panel = panel

        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            parentWindow = parent
            parent.beginSheet(panel, completionHandler: nil)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func closePanel() {
        guard let panel = panel else { return }
        panel.delegate = nil
        if let parent = parentWindow {
            parent.endSheet(panel)
        }
        panel.orderOut(nil)
        self.panel = nil
        parentWindow = nil
        primaryButton = nil
        stopButton = nil
    }

    @objc private func primaryTapped() {
        guard let request = request else { return }
        if request.isVideo {
            startRecording()
        } else {
            takePhoto()
        }
    }

    @objc private func stopTapped() {
        movieOutput?.stopRecording()
    }

    @objc private func cancelTapped() {
        cancelCapture()
    }

    /// Closing the panel with the title-bar button behaves like Cancel.
    func windowWillClose(_ notification: Notification) {
        cancelCapture()
    }

    private func cancelCapture() {
        cancelRequested = true
        if let movie = movieOutput, movie.isRecording {
            // The delegate finishes (and deletes the file) once recording stops.
            movie.stopRecording()
            return
        }
        finish(nil)
    }

    // MARK: - Photo

    private func takePhoto() {
        guard let output = photoOutput else { return }
        primaryButton?.isEnabled = false
        var settings = AVCapturePhotoSettings()
        if output.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.pendingResult != nil else { return }
            if let error = error {
                self.finish(FlutterError(
                    code: "io_error",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            guard let data = photo.fileDataRepresentation(), let request = self.request else {
                self.finish(FlutterError(
                    code: "io_error",
                    message: "The camera did not return a photo",
                    details: nil
                ))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let map = try self.savePhoto(data: data, request: request)
                    DispatchQueue.main.async { self.finish(["file": map]) }
                } catch {
                    DispatchQueue.main.async {
                        self.finish(FlutterError(
                            code: "io_error",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    private func savePhoto(data: Data, request: Request) throws -> [String: Any?] {
        let name = "\(UUID().uuidString).jpg"
        let url = try cacheDirectory().appendingPathComponent(name)
        let needsEncode = request.maxWidth != nil || request.maxHeight != nil
            || request.imageQuality != nil
        if !needsEncode {
            try data.write(to: url)
            return try map(for: url, name: name, withData: request.withData)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else {
            throw CaptureError.configuration("Unable to read the captured photo")
        }
        let (targetWidth, targetHeight) = Self.targetSize(
            width: width, height: height,
            maxWidth: request.maxWidth, maxHeight: request.maxHeight
        )
        // The thumbnail API keeps the aspect ratio, so the longer side decides.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetWidth, targetHeight),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, "public.jpeg" as CFString, 1, nil
              )
        else {
            throw CaptureError.configuration("Unable to encode the captured photo")
        }
        let quality = Double(request.imageQuality ?? 100) / 100
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.configuration("Unable to write the captured photo")
        }
        return try map(for: url, name: name, withData: request.withData)
    }

    /// Size after downscaling to fit `maxWidth` x `maxHeight` (never enlarges).
    static func targetSize(
        width: Double, height: Double, maxWidth: Double?, maxHeight: Double?
    ) -> (Double, Double) {
        var factor = 1.0
        if let maxWidth = maxWidth, maxWidth > 0 { factor = max(factor, width / maxWidth) }
        if let maxHeight = maxHeight, maxHeight > 0 { factor = max(factor, height / maxHeight) }
        if factor <= 1 { return (width, height) }
        return (max(1, (width / factor).rounded(.down)), max(1, (height / factor).rounded(.down)))
    }

    // MARK: - Video

    private func startRecording() {
        guard let movie = movieOutput, !movie.isRecording else { return }
        do {
            let url = try cacheDirectory().appendingPathComponent("\(UUID().uuidString).mov")
            recordingURL = url
            movie.startRecording(to: url, recordingDelegate: self)
            primaryButton?.isHidden = true
            stopButton?.isHidden = false
        } catch {
            finish(FlutterError(
                code: "io_error",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.pendingResult != nil else { return }
            // Reaching `maxDuration` is reported as an error that still
            // carries a finished recording.
            let nsError = error as NSError?
            let finishedOK = nsError == nil
                || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
            if self.cancelRequested {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.finish(nil)
                return
            }
            guard finishedOK else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.finish(FlutterError(
                    code: "io_error",
                    message: nsError?.localizedDescription ?? "Recording failed",
                    details: nil
                ))
                return
            }
            let withData = self.request?.withData ?? false
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let map = try self.map(
                        for: outputFileURL,
                        name: outputFileURL.lastPathComponent,
                        withData: withData
                    )
                    DispatchQueue.main.async { self.finish(["file": map]) }
                } catch {
                    DispatchQueue.main.async {
                        self.finish(FlutterError(
                            code: "io_error",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private enum CaptureError: LocalizedError {
        case configuration(String)

        var errorDescription: String? {
            switch self {
            case let .configuration(message): return message
            }
        }
    }

    private func cacheDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func map(for url: URL, name: String, withData: Bool) throws -> [String: Any?] {
        var size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var bytes: FlutterStandardTypedData?
        if withData {
            let data = try Data(contentsOf: url)
            bytes = FlutterStandardTypedData(bytes: data)
            size = data.count
        }
        return [
            "name": name,
            "size": size,
            "path": url.path,
            "bytes": bytes,
            "identifier": url.absoluteString,
        ]
    }

    /// Stops the camera, closes the UI and answers the pending call once.
    private func finish(_ value: Any?) {
        let result = pendingResult
        pendingResult = nil
        request = nil
        cancelRequested = false
        recordingURL = nil
        let session = self.session
        self.session = nil
        photoOutput = nil
        movieOutput = nil
        closePanel()
        sessionQueue.async { session?.stopRunning() }
        result?(value)
    }
}
