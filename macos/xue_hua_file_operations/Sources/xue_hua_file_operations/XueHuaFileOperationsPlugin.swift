import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

public class XueHuaFileOperationsPlugin: NSObject, FlutterPlugin {
    private let cameraCapture = CameraCapture()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "xue_hua_file_operations",
            binaryMessenger: registrar.messenger
        )
        let instance = XueHuaFileOperationsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickFile":
            pick(call: call, result: result, multiple: false, directory: false)
        case "pickFiles":
            pick(call: call, result: result, multiple: true, directory: false)
        case "pickDirectory":
            pick(call: call, result: result, multiple: false, directory: true)
        case "saveFile":
            saveFile(call: call, result: result)
        case "saveToGallery":
            GallerySaver.save(call: call, result: result)
        case "galleryPermissionStatus":
            GallerySaver.permissionStatus(call: call, result: result)
        case "requestGalleryPermission":
            GallerySaver.requestPermission(call: call, result: result)
        case "openFile":
            openFile(call: call, result: result)
        case "openAppSettings":
            openAppSettings(result: result)
        case "capturePhoto":
            cameraCapture.capture(call: call, result: result, isVideo: false)
        case "captureVideo":
            cameraCapture.capture(call: call, result: result, isVideo: true)
        case "retrieveLostCapture":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // Automated UI-test hooks (skip native NSOpenPanel / NSSavePanel). Set by
    // flutter_driver / the launch shell; no-ops when unset:
    //   XUE_HUA_TEST_PICK_FILE=<abs path>              single-file pick
    //   XUE_HUA_TEST_PICK_FILES=<a>:<b>                multi-file (colon, like Linux)
    //   XUE_HUA_TEST_PICK_DIR=<abs dir>                directory pick
    //   XUE_HUA_TEST_SAVE_FILE=<abs path>              save-as destination
    //   XUE_HUA_TEST_OPEN_FILE=skip                    validate path, do not open
    // Any pick/save value may be the literal "CANCEL" to simulate cancel.
    private static let testPickFileEnv = "XUE_HUA_TEST_PICK_FILE"
    private static let testPickFilesEnv = "XUE_HUA_TEST_PICK_FILES"
    private static let testPickDirEnv = "XUE_HUA_TEST_PICK_DIR"
    private static let testSaveFileEnv = "XUE_HUA_TEST_SAVE_FILE"
    private static let testOpenFileEnv = "XUE_HUA_TEST_OPEN_FILE"

    private static func env(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func testHookIsCancel(_ value: String) -> Bool {
        value == "CANCEL"
    }

    private static func splitColonPaths(_ value: String) -> [String] {
        value.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }


    private func contentTypes(from args: [String: Any]?) -> [UTType] {
        var types: [UTType] = []
        if let mimes = args?["allowedMimeTypes"] as? [String] {
            for mime in mimes {
                if let t = UTType(mimeType: mime) {
                    types.append(t)
                }
            }
        }
        if let exts = args?["allowedExtensions"] as? [String] {
            for ext in exts {
                let clean = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
                if let t = UTType(filenameExtension: clean) {
                    types.append(t)
                }
            }
        }
        if !types.isEmpty {
            return types
        }

        switch args?["type"] as? String {
        case "image": return [.image]
        case "video": return [.movie]
        case "media": return [.image, .movie]
        case "audio": return [.audio]
        default: return []
        }
    }

    private func pick(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        multiple: Bool,
        directory: Bool
    ) {
        let args = call.arguments as? [String: Any]
        let withData = args?["withData"] as? Bool ?? false
        let maxFiles = args?["maxFiles"] as? Int

        if directory {
            if let hook = Self.env(Self.testPickDirEnv) {
                if Self.testHookIsCancel(hook) {
                    result(nil)
                    return
                }
                let url = URL(fileURLWithPath: hook)
                result([
                    "path": url.path,
                    "name": url.lastPathComponent,
                    "identifier": url.absoluteString,
                ])
                return
            }
        } else {
            let hookEnv = multiple ? Self.testPickFilesEnv : Self.testPickFileEnv
            var hook = Self.env(hookEnv)
            // Allow the single-file env for multi when the multi env is unset.
            if multiple && hook == nil {
                hook = Self.env(Self.testPickFileEnv)
            }
            if let hook {
                if Self.testHookIsCancel(hook) {
                    result(nil)
                    return
                }
                let paths = Self.splitColonPaths(hook)
                if paths.isEmpty {
                    result(nil)
                    return
                }
                if !multiple {
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let file = try Self.fileMap(
                                from: URL(fileURLWithPath: paths[0]),
                                withData: withData
                            )
                            DispatchQueue.main.async { result(["file": file]) }
                        } catch {
                            DispatchQueue.main.async {
                                result(FlutterError(
                                    code: "io_error",
                                    message: error.localizedDescription,
                                    details: nil
                                ))
                            }
                        }
                    }
                    return
                }
                if let max = maxFiles, paths.count > max {
                    result(FlutterError(
                        code: "too_many_files",
                        message: "Selected \(paths.count) files but maxFiles is \(max)",
                        details: ["selected": paths.count, "maxFiles": max]
                    ))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let files = try paths.map {
                            try Self.fileMap(from: URL(fileURLWithPath: $0), withData: withData)
                        }
                        DispatchQueue.main.async { result(["files": files]) }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(
                                code: "io_error",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        }
                    }
                }
                return
            }
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        panel.allowsMultipleSelection = multiple && !directory
        panel.canCreateDirectories = false
        if let title = args?["dialogTitle"] as? String {
            panel.message = title
        }
        let types = contentTypes(from: args)
        if !types.isEmpty, !directory {
            panel.allowedContentTypes = types
        }

        panel.begin { response in
            guard response == .OK else {
                result(nil)
                return
            }

            if directory {
                guard let url = panel.url else {
                    result(nil)
                    return
                }
                result([
                    "path": url.path,
                    "name": url.lastPathComponent,
                    "identifier": url.absoluteString,
                ])
                return
            }

            let urls = panel.urls
            if urls.isEmpty {
                result(nil)
                return
            }

            if multiple, let max = maxFiles, urls.count > max {
                result(FlutterError(
                    code: "too_many_files",
                    message: "Selected \(urls.count) files but maxFiles is \(max)",
                    details: ["selected": urls.count, "maxFiles": max]
                ))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    if multiple {
                        let files = try urls.map { try Self.fileMap(from: $0, withData: withData) }
                        DispatchQueue.main.async { result(["files": files]) }
                    } else {
                        let file = try Self.fileMap(from: urls[0], withData: withData)
                        DispatchQueue.main.async { result(["file": file]) }
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "io_error",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    private func saveFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let fileName = args?["fileName"] as? String ?? "file"
        let flutterData = args?["bytes"] as? FlutterStandardTypedData
        let sourcePath = args?["sourcePath"] as? String

        if flutterData == nil, sourcePath == nil || sourcePath!.isEmpty {
            result(FlutterError(
                code: "invalid_args",
                message: "Either bytes or sourcePath must be provided",
                details: nil
            ))
            return
        }

        let writeDest: (URL) -> Void = { url in
            do {
                if let flutterData = flutterData {
                    try flutterData.data.write(to: url, options: .atomic)
                } else if let sourcePath = sourcePath {
                    let source = URL(fileURLWithPath: sourcePath)
                    guard FileManager.default.fileExists(atPath: source.path) else {
                        result(FlutterError(
                            code: "not_found",
                            message: "File not found: \(sourcePath)",
                            details: nil
                        ))
                        return
                    }
                    let access = source.startAccessingSecurityScopedResource()
                    defer {
                        if access {
                            source.stopAccessingSecurityScopedResource()
                        }
                    }
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: source, to: url)
                }
                result([
                    "path": url.path,
                    "name": url.lastPathComponent,
                ])
            } catch {
                result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
            }
        }

        if let hook = Self.env(Self.testSaveFileEnv) {
            if Self.testHookIsCancel(hook) {
                result(nil)
                return
            }
            writeDest(URL(fileURLWithPath: hook))
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        if let title = args?["dialogTitle"] as? String {
            panel.message = title
        }
        if let exts = args?["allowedExtensions"] as? [String], !exts.isEmpty {
            panel.allowedContentTypes = exts.compactMap {
                let clean = $0.hasPrefix(".") ? String($0.dropFirst()) : $0
                return UTType(filenameExtension: clean)
            }
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                result(nil)
                return
            }
            writeDest(url)
        }
    }

    private func openFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let path = args?["path"] as? String
        let identifier = args?["identifier"] as? String

        let url: URL?
        if let path = path, !path.isEmpty {
            url = URL(fileURLWithPath: path)
        } else if let identifier = identifier, !identifier.isEmpty {
            url = URL(string: identifier) ?? URL(fileURLWithPath: identifier)
        } else {
            result(FlutterError(
                code: "invalid_args",
                message: "Either path or identifier must be provided",
                details: nil
            ))
            return
        }

        guard let url = url else {
            result(FlutterError(code: "not_found", message: "Invalid file URL", details: nil))
            return
        }

        if Self.env(Self.testOpenFileEnv) == "skip" {
            if !FileManager.default.fileExists(atPath: url.path) {
                result(FlutterError(code: "not_found", message: "File not found", details: nil))
                return
            }
            result(true)
            return
        }

        let ok = NSWorkspace.shared.open(url)
        if ok {
            result(true)
        } else {
            result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
        }
    }

    private func openAppSettings(result: @escaping FlutterResult) {
        let apply = {
            let candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Photos",
                "x-apple.systempreferences:",
            ]
            for spec in candidates {
                if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                    result(true)
                    return
                }
            }
            result(FlutterError(
                code: "unsupported",
                message: "Unable to open System Settings",
                details: nil
            ))
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func fileMap(from url: URL, withData: Bool) throws -> [String: Any?] {
        // Sandbox: panel URLs carry an implicit grant, but scoped access is
        // required for URLs resolved from bookmarks; harmless otherwise.
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let name = values.name ?? url.lastPathComponent
        var size = values.fileSize ?? 0
        var bytes: FlutterStandardTypedData?

        if withData {
            let data = try Data(contentsOf: url)
            bytes = FlutterStandardTypedData(bytes: data)
            size = data.count
        } else if size == 0 {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        }

        return [
            "name": name,
            "size": size,
            "path": url.path,
            "bytes": bytes,
            "identifier": url.absoluteString,
        ]
    }
}
