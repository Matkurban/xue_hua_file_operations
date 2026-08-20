import Flutter
import MobileCoreServices
import PhotosUI
import UIKit
import UniformTypeIdentifiers

public class XueHuaFileOperationsPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate,
    UIDocumentInteractionControllerDelegate
{
    private static let bookmarkPrefix = "xuehua-bookmark:"

    private var pendingResult: FlutterResult?
    private var pendingWithData = false
    private var pendingMaxFiles: Int?
    private var pendingMode: Mode = .pickFile
    private var saveFileName: String = "file"
    private var documentInteractionController: UIDocumentInteractionController?
    private var documentInteractionScopedAccess = false

    private enum Mode {
        case pickFile
        case pickFiles
        case pickDirectory
        case saveFile
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "xue_hua_file_operations",
            binaryMessenger: registrar.messenger()
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                return topViewController(from: root)
            }
        }
        return nil
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return root
    }

    @available(iOS 14.0, *)
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
        default: return [.item]
        }
    }

    private func contentTypeIdentifiers(from args: [String: Any]?) -> [String] {
        var types: [String] = []
        if let mimes = args?["allowedMimeTypes"] as? [String] {
            for mime in mimes {
                if let identifier = utiIdentifier(mimeType: mime) {
                    types.append(identifier)
                }
            }
        }
        if let exts = args?["allowedExtensions"] as? [String] {
            for ext in exts {
                let clean = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
                if let identifier = utiIdentifier(filenameExtension: clean) {
                    types.append(identifier)
                }
            }
        }
        if !types.isEmpty {
            return types
        }

        switch args?["type"] as? String {
        case "image": return ["public.image"]
        case "video": return ["public.movie"]
        case "media": return ["public.image", "public.movie"]
        case "audio": return ["public.audio"]
        default: return ["public.item"]
        }
    }

    private func utiIdentifier(mimeType: String) -> String? {
        if #available(iOS 14.0, *) {
            return UTType(mimeType: mimeType)?.identifier
        }
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassMIMEType,
            mimeType as CFString,
            nil
        )?.takeRetainedValue() as String?
    }

    private func utiIdentifier(filenameExtension: String) -> String? {
        if #available(iOS 14.0, *) {
            return UTType(filenameExtension: filenameExtension)?.identifier
        }
        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            filenameExtension as CFString,
            nil
        )?.takeRetainedValue() as String?
    }

    private func makeOpenPicker(
        directory: Bool,
        args: [String: Any]?
    ) -> UIDocumentPickerViewController {
        if #available(iOS 14.0, *) {
            let types: [UTType] = directory ? [.folder] : contentTypes(from: args)
            return UIDocumentPickerViewController(
                forOpeningContentTypes: types,
                asCopy: !directory
            )
        }
        let identifiers = directory ? ["public.folder"] : contentTypeIdentifiers(from: args)
        return UIDocumentPickerViewController(
            documentTypes: identifiers,
            in: directory ? .open : .import
        )
    }

    private func makeExportPicker(url: URL) -> UIDocumentPickerViewController {
        if #available(iOS 14.0, *) {
            return UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        }
        return UIDocumentPickerViewController(url: url, in: .exportToService)
    }

    private func pick(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        multiple: Bool,
        directory: Bool
    ) {
        guard pendingResult == nil else {
            result(FlutterError(
                code: "invalid_args",
                message: "Another file operation is in progress",
                details: nil
            ))
            return
        }
        guard let presenter = rootViewController() else {
            result(FlutterError(code: "unknown", message: "No view controller", details: nil))
            return
        }

        let args = call.arguments as? [String: Any]
        pendingResult = result
        pendingWithData = args?["withData"] as? Bool ?? false
        pendingMaxFiles = args?["maxFiles"] as? Int
        pendingMode = directory ? .pickDirectory : (multiple ? .pickFiles : .pickFile)

        // Media types must go through the Photos picker: the document picker
        // browses the Files app, which cannot show the photo library.
        if !directory, #available(iOS 14.0, *),
           let mediaType = photoPickerType(from: args)
        {
            presentPhotoPicker(
                type: mediaType,
                multiple: multiple,
                maxFiles: pendingMaxFiles,
                presenter: presenter
            )
            return
        }

        let picker = makeOpenPicker(directory: directory, args: args)
        picker.delegate = self
        picker.allowsMultipleSelection = multiple && !directory
        presenter.present(picker, animated: true)
    }

    /// Returns the media type when the request should use the Photos picker,
    /// or `nil` when the document picker should be used instead.
    private func photoPickerType(from args: [String: Any]?) -> String? {
        if let mimes = args?["allowedMimeTypes"] as? [String], !mimes.isEmpty {
            return nil
        }
        if let exts = args?["allowedExtensions"] as? [String], !exts.isEmpty {
            return nil
        }
        switch args?["type"] as? String {
        case "image": return "image"
        case "video": return "video"
        case "media": return "media"
        default: return nil
        }
    }

    @available(iOS 14.0, *)
    private func presentPhotoPicker(
        type: String,
        multiple: Bool,
        maxFiles: Int?,
        presenter: UIViewController
    ) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        switch type {
        case "image": config.filter = .images
        case "video": config.filter = .videos
        default: config.filter = .any(of: [.images, .videos])
        }
        config.selectionLimit = multiple ? (maxFiles ?? 0) : 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    @available(iOS 14.0, *)
    private func loadPhotoPickerResults(
        _ results: [PHPickerResult],
        withData: Bool,
        completion: @escaping ([[String: Any?]], Error?) -> Void
    ) {
        let group = DispatchGroup()
        var maps = [[String: Any?]?](repeating: nil, count: results.count)
        var firstError: Error?
        let lock = NSLock()

        for (index, item) in results.enumerated() {
            group.enter()
            let provider = item.itemProvider
            let assetIdentifier = item.assetIdentifier
            let typeIdentifier = provider.hasItemConformingToTypeIdentifier(
                UTType.movie.identifier
            ) ? UTType.movie.identifier : UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
                [weak self] url, error in
                defer { group.leave() }
                guard let self = self else { return }
                if let url = url {
                    do {
                        // The provider URL is only valid inside this callback;
                        // copy into the plugin cache before returning.
                        let map = try self.copiedFileMap(
                            from: url,
                            name: url.lastPathComponent,
                            withData: withData,
                            identifier: assetIdentifier
                        )
                        lock.lock()
                        maps[index] = map
                        lock.unlock()
                        return
                    } catch {
                        lock.lock()
                        if firstError == nil { firstError = error }
                        lock.unlock()
                        return
                    }
                }
                lock.lock()
                if firstError == nil {
                    firstError = error ?? NSError(
                        domain: "xue_hua_file_operations",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Unable to load picked media",
                        ]
                    )
                }
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion([], error)
            } else {
                completion(maps.compactMap { $0 }, nil)
            }
        }
    }

    private func saveFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard pendingResult == nil else {
            result(FlutterError(
                code: "invalid_args",
                message: "Another file operation is in progress",
                details: nil
            ))
            return
        }
        guard let presenter = rootViewController() else {
            result(FlutterError(code: "unknown", message: "No view controller", details: nil))
            return
        }

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

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            if let flutterData = flutterData {
                try flutterData.data.write(to: tempURL, options: .atomic)
            } else if let sourcePath = sourcePath {
                let source = URL(fileURLWithPath: sourcePath)
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: source, to: tempURL)
            }

            pendingResult = result
            pendingMode = .saveFile
            saveFileName = fileName

            let picker = makeExportPicker(url: tempURL)
            picker.delegate = self
            presenter.present(picker, animated: true)
        } catch {
            result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
        }
    }

    private func openFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let path = args?["path"] as? String
        let identifier = args?["identifier"] as? String

        let hasPath = path != nil && !(path!.isEmpty)
        let hasIdentifier = identifier != nil && !(identifier!.isEmpty)
        if !hasPath && !hasIdentifier {
            result(FlutterError(
                code: "invalid_args",
                message: "Either path or identifier must be provided",
                details: nil
            ))
            return
        }

        guard let resolved = resolveURL(path: path, identifier: identifier) else {
            result(FlutterError(
                code: "not_found",
                message: "Unable to resolve path or identifier",
                details: nil
            ))
            return
        }

        // UIApplication.open always fails for file URLs; go straight to the
        // document interaction controller for local files.
        if resolved.url.isFileURL {
            presentDocumentInteraction(for: resolved.url, result: result)
            return
        }

        UIApplication.shared.open(resolved.url, options: [:]) { success in
            if success {
                result(true)
            } else {
                result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
            }
        }
    }

    private func presentDocumentInteraction(for url: URL, result: @escaping FlutterResult) {
        guard let presenter = rootViewController() else {
            result(FlutterError(code: "unknown", message: "No view controller", details: nil))
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        let controller = UIDocumentInteractionController(url: url)
        controller.delegate = self
        documentInteractionController = controller
        documentInteractionScopedAccess = access
        let presented = controller.presentPreview(animated: true)
            || controller.presentOpenInMenu(
                from: presenter.view.bounds,
                in: presenter.view,
                animated: true
            )
        if !presented {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
            documentInteractionController = nil
            result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
        } else {
            // Security-scoped access (if any) is released in the delegate
            // callbacks when the interaction ends.
            result(true)
        }
    }

    private func openAppSettings(result: @escaping FlutterResult) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(FlutterError(
                code: "unsupported",
                message: "Unable to open Settings",
                details: nil
            ))
            return
        }
        let apply = {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    result(true)
                } else {
                    result(FlutterError(
                        code: "unsupported",
                        message: "Unable to open Settings",
                        details: nil
                    ))
                }
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    public func documentInteractionControllerDidEndPreview(
        _ controller: UIDocumentInteractionController
    ) {
        if documentInteractionScopedAccess {
            controller.url?.stopAccessingSecurityScopedResource()
            documentInteractionScopedAccess = false
        }
        documentInteractionController = nil
    }

    public func documentInteractionController(
        _: UIDocumentInteractionController,
        willBeginSendingToApplication _: String?
    ) {
        // Keep access while sending; stop after dismiss via didDismissOpenInMenu if needed.
    }

    public func documentInteractionControllerDidDismissOpenInMenu(
        _ controller: UIDocumentInteractionController
    ) {
        if documentInteractionScopedAccess {
            controller.url?.stopAccessingSecurityScopedResource()
            documentInteractionScopedAccess = false
        }
        documentInteractionController = nil
    }

    public func documentInteractionControllerViewControllerForPreview(
        _: UIDocumentInteractionController
    ) -> UIViewController {
        rootViewController() ?? UIViewController()
    }

    private struct ResolvedURL {
        let url: URL
    }

    private func resolveURL(path: String?, identifier: String?) -> ResolvedURL? {
        if let identifier = identifier, !identifier.isEmpty {
            if identifier.hasPrefix(Self.bookmarkPrefix) {
                let encoded = String(identifier.dropFirst(Self.bookmarkPrefix.count))
                guard let data = Data(base64Encoded: encoded) else { return nil }
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: data,
                        options: [],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    return ResolvedURL(url: url)
                } catch {
                    return nil
                }
            }
            return ResolvedURL(url: URL(string: identifier) ?? URL(fileURLWithPath: identifier))
        }
        if let path = path, !path.isEmpty {
            return ResolvedURL(url: URL(fileURLWithPath: path))
        }
        return nil
    }

    private func securityScopedBookmarkIdentifier(for url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return Self.bookmarkPrefix + bookmark.base64EncodedString()
    }

    public func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        let result = pendingResult
        clearPending()
        result?(nil)
    }

    public func documentPicker(
        _: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let result = pendingResult
        let mode = pendingMode
        let withData = pendingWithData
        let maxFiles = pendingMaxFiles
        let fileName = saveFileName
        clearPending()
        guard let result = result else { return }

        switch mode {
        case .pickFile:
            guard let url = urls.first else {
                result(nil)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    let map = try self.fileMap(from: url, withData: withData)
                    DispatchQueue.main.async { result(["file": map]) }
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
        case .pickFiles:
            if let max = maxFiles, urls.count > max {
                result(FlutterError(
                    code: "too_many_files",
                    message: "Selected \(urls.count) files but maxFiles is \(max)",
                    details: ["selected": urls.count, "maxFiles": max]
                ))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    let files = try urls.map { try self.fileMap(from: $0, withData: withData) }
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
        case .pickDirectory:
            guard let url = urls.first else {
                result(nil)
                return
            }
            do {
                // Persist access via security-scoped bookmark; path is for display only.
                let identifier = try securityScopedBookmarkIdentifier(for: url)
                result([
                    "path": url.path,
                    "name": url.lastPathComponent,
                    "identifier": identifier,
                ])
            } catch {
                result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
            }
        case .saveFile:
            guard let url = urls.first else {
                result(nil)
                return
            }
            result([
                "path": url.path,
                "name": fileName,
            ])
        }
    }

    private func fileMap(from url: URL, withData: Bool) throws -> [String: Any?] {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.nameKey])
        let name = values.name ?? url.lastPathComponent
        return try copiedFileMap(
            from: url,
            name: name,
            withData: withData,
            identifier: url.absoluteString
        )
    }

    /// Copies `url` into the plugin cache directory and builds the wire map.
    private func copiedFileMap(
        from url: URL,
        name: String,
        withData: Bool,
        identifier: String?
    ) throws -> [String: Any?] {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let dest = cacheURL.appendingPathComponent("\(UUID().uuidString)_\(name)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)

        var size = (try? dest.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var bytes: FlutterStandardTypedData?
        if withData {
            let data = try Data(contentsOf: dest)
            bytes = FlutterStandardTypedData(bytes: data)
            size = data.count
        }

        return [
            "name": name,
            "size": size,
            "path": dest.path,
            "bytes": bytes,
            "identifier": identifier,
        ]
    }

    private func clearPending() {
        pendingResult = nil
        pendingWithData = false
        pendingMaxFiles = nil
        pendingMode = .pickFile
        saveFileName = "file"
    }
}

@available(iOS 14.0, *)
extension XueHuaFileOperationsPlugin: PHPickerViewControllerDelegate {
    public func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)
        let result = pendingResult
        let mode = pendingMode
        let withData = pendingWithData
        clearPending()
        guard let result = result else { return }
        if results.isEmpty {
            result(nil)
            return
        }
        loadPhotoPickerResults(results, withData: withData) { maps, error in
            if let error = error {
                result(FlutterError(
                    code: "io_error",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            if mode == .pickFile {
                if let first = maps.first {
                    result(["file": first])
                } else {
                    result(nil)
                }
            } else {
                result(["files": maps])
            }
        }
    }
}
