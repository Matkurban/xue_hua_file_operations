import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

public class XueHuaFileOperationsPlugin: NSObject, FlutterPlugin {
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
        case "openFile":
            openFile(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
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

            if multiple {
                if let max = maxFiles, urls.count > max {
                    result(FlutterError(
                        code: "too_many_files",
                        message: "Selected \(urls.count) files but maxFiles is \(max)",
                        details: ["selected": urls.count, "maxFiles": max]
                    ))
                    return
                }
                do {
                    let files = try urls.map { try Self.fileMap(from: $0, withData: withData) }
                    result(["files": files])
                } catch {
                    result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
                }
            } else {
                do {
                    try result(["file": Self.fileMap(from: urls[0], withData: withData)])
                } catch {
                    result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
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
            do {
                if let flutterData = flutterData {
                    try flutterData.data.write(to: url, options: .atomic)
                } else if let sourcePath = sourcePath {
                    let source = URL(fileURLWithPath: sourcePath)
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

        let ok = NSWorkspace.shared.open(url)
        if ok {
            result(true)
        } else {
            result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
        }
    }

    private static func fileMap(from url: URL, withData: Bool) throws -> [String: Any?] {
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
