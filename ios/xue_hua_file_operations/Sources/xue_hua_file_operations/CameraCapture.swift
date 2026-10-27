import AVFoundation
import Flutter
import UniformTypeIdentifiers
import UIKit

/// Presents the system camera (`UIImagePickerController`) to take a photo or
/// record a video and reports the result through a `FlutterResult`.
final class CameraCapture: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
{
    private struct Request {
        let isVideo: Bool
        let preferredCamera: String
        let maxDurationSeconds: Int?
        let maxWidth: Double?
        let maxHeight: Double?
        let imageQuality: Int?
        let withData: Bool
    }

    private var pendingResult: FlutterResult?
    private var request: Request?

    /// `true` while a camera session is on screen.
    var isBusy: Bool { pendingResult != nil }

    func capture(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        isVideo: Bool,
        presenter: UIViewController
    ) {
        let args = call.arguments as? [String: Any]
        let request = Request(
            isVideo: isVideo,
            preferredCamera: args?["preferredCamera"] as? String ?? "rear",
            maxDurationSeconds: (args?["maxDurationSeconds"] as? NSNumber)?.intValue,
            maxWidth: (args?["maxWidth"] as? NSNumber)?.doubleValue,
            maxHeight: (args?["maxHeight"] as? NSNumber)?.doubleValue,
            imageQuality: (args?["imageQuality"] as? NSNumber)?.intValue,
            withData: args?["withData"] as? Bool ?? false
        )

        // Without these keys iOS terminates the app as soon as the camera opens.
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
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            result(FlutterError(
                code: "unsupported",
                message: "No camera is available on this device",
                details: nil
            ))
            return
        }

        pendingResult = result
        self.request = request
        requestCameraAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.finish(FlutterError(
                    code: "permission_denied",
                    message: "The user did not allow camera access.",
                    details: nil
                ))
                return
            }
            self.present(from: presenter)
        }
    }

    private func requestCameraAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    private func present(from presenter: UIViewController) {
        guard let request = request else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [
            request.isVideo ? UTType.movie.identifier : UTType.image.identifier,
        ]
        if request.isVideo {
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
            if let seconds = request.maxDurationSeconds, seconds > 0 {
                picker.videoMaximumDuration = TimeInterval(seconds)
            }
        }
        let device: UIImagePickerController.CameraDevice =
            request.preferredCamera == "front" ? .front : .rear
        if UIImagePickerController.isCameraDeviceAvailable(device) {
            picker.cameraDevice = device
        }
        picker.delegate = self
        presenter.present(picker, animated: true) { [weak self, weak picker] in
            self?.runTestAutomation(picker)
        }
    }

    /// Test hook for UI tests (the system camera UI is outside Flutter's
    /// widget tree): with `XUE_HUA_CAMERA_TEST_AUTO=1` in the process
    /// environment the shutter is triggered ~1.5 s after the camera appears
    /// (`takePicture()` / `startVideoCapture()`, recording is stopped ~2 s
    /// later). Without the variable nothing happens.
    private func runTestAutomation(_ picker: UIImagePickerController?) {
        guard ProcessInfo.processInfo.environment["XUE_HUA_CAMERA_TEST_AUTO"] == "1",
              let picker = picker, let request = request else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak picker] in
            guard let picker = picker else { return }
            if request.isVideo {
                _ = picker.startVideoCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak picker] in
                    picker?.stopVideoCapture()
                }
            } else {
                picker.takePicture()
            }
        }
    }

    private func finish(_ value: Any?) {
        let result = pendingResult
        pendingResult = nil
        request = nil
        result?(value)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(nil)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let request = request else {
            finish(nil)
            return
        }
        do {
            let map: [String: Any?]
            if request.isVideo {
                guard let url = info[.mediaURL] as? URL else {
                    throw CaptureError.noMedia
                }
                map = try fileMap(copying: url, request: request)
            } else {
                guard let image = info[.originalImage] as? UIImage else {
                    throw CaptureError.noMedia
                }
                map = try photoMap(image: image, request: request)
            }
            finish(["file": map])
        } catch {
            finish(FlutterError(
                code: "io_error",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private enum CaptureError: LocalizedError {
        case noMedia
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .noMedia: return "The camera did not return any media"
            case .encodeFailed: return "Unable to encode the captured photo"
            }
        }
    }

    // MARK: - Result building

    private func cacheDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileMap(copying url: URL, request: Request) throws -> [String: Any?] {
        let name = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
        let dest = try cacheDirectory().appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: dest)
        return try map(for: dest, name: name, withData: request.withData)
    }

    private func photoMap(image: UIImage, request: Request) throws -> [String: Any?] {
        let scaled = Self.scaledImage(
            image, maxWidth: request.maxWidth, maxHeight: request.maxHeight
        )
        let quality = CGFloat(request.imageQuality ?? 100) / 100
        guard let data = scaled.jpegData(compressionQuality: quality) else {
            throw CaptureError.encodeFailed
        }
        let name = "\(UUID().uuidString).jpg"
        let dest = try cacheDirectory().appendingPathComponent(name)
        try data.write(to: dest)
        return try map(for: dest, name: name, withData: request.withData)
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

    /// Downscales `image` to fit `maxWidth` x `maxHeight` (aspect ratio kept,
    /// never enlarged). Drawing also bakes the EXIF orientation into the pixels.
    static func scaledImage(_ image: UIImage, maxWidth: Double?, maxHeight: Double?) -> UIImage {
        let originalWidth = Double(image.size.width)
        let originalHeight = Double(image.size.height)
        var width = originalWidth
        var height = originalHeight

        if maxWidth != nil || maxHeight != nil {
            let aspectRatio = originalWidth / originalHeight
            if let maxWidth = maxWidth { width = min(maxWidth.rounded(), originalWidth) }
            if let maxHeight = maxHeight { height = min(maxHeight.rounded(), originalHeight) }
            let downscale = (maxWidth.map { $0 < originalWidth } ?? false)
                || (maxHeight.map { $0 < originalHeight } ?? false)
            if downscale {
                let widthForMaxHeight = height * aspectRatio
                let heightForMaxWidth = width / aspectRatio
                if heightForMaxWidth > height {
                    width = widthForMaxHeight.rounded()
                } else {
                    height = heightForMaxWidth.rounded()
                }
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: max(width, 1), height: max(height, 1)), format: format
        )
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: max(width, 1), height: max(height, 1)))
        }
    }
}
