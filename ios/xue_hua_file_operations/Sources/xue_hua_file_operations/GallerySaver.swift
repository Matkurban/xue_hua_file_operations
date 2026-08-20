import Flutter
import Photos

enum GallerySaver {
    static func permissionStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(wireName(for: currentStatus(forAlbum: wantsAlbumAccess(from: call))))
    }

    static func requestPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        requestAccess(forAlbum: wantsAlbumAccess(from: call)) { status in
            result(wireName(for: status))
        }
    }

    static func save(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let fileName = args?["fileName"] as? String ?? "file"
        let flutterData = args?["bytes"] as? FlutterStandardTypedData
        let sourcePath = args?["sourcePath"] as? String
        let type = args?["type"] as? String
        let albumName = (args?["albumName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if flutterData == nil, sourcePath == nil || sourcePath!.isEmpty {
            result(FlutterError(
                code: "invalid_args",
                message: "Either bytes or sourcePath must be provided",
                details: nil
            ))
            return
        }
        guard type == "image" || type == "video" else {
            result(FlutterError(
                code: "invalid_args",
                message: "type must be image or video",
                details: nil
            ))
            return
        }

        let isVideo = type == "video"
        let wantsAlbum = !(albumName ?? "").isEmpty

        do {
            let fileURL = try prepareFileURL(
                fileName: fileName,
                bytes: flutterData?.data,
                sourcePath: sourcePath
            )
            requestAccess(forAlbum: wantsAlbum) { status in
                switch status {
                case .authorized:
                    let existingAlbum: PHAssetCollection?
                    if wantsAlbum, let albumName = albumName {
                        existingAlbum = fetchAlbum(named: albumName)
                    } else {
                        existingAlbum = nil
                    }
                    performSave(
                        fileURL: fileURL,
                        createdTemp: true,
                        isVideo: isVideo,
                        albumName: wantsAlbum ? albumName : nil,
                        existingAlbum: existingAlbum,
                        result: result
                    )
                case .denied, .restricted:
                    cleanupTempIfNeeded(fileURL, sourcePath: sourcePath)
                    result(FlutterError(
                        code: "permission_denied",
                        message: "Photo library access was denied",
                        details: nil
                    ))
                default:
                    // limited (iOS 14+): save without a custom album.
                    // notDetermined / unknown after the prompt: still try to save.
                    performSave(
                        fileURL: fileURL,
                        createdTemp: true,
                        isVideo: isVideo,
                        albumName: nil,
                        existingAlbum: nil,
                        result: result
                    )
                }
            }
        } catch let error as NSError {
            let code = error.domain == NSCocoaErrorDomain &&
                error.code == NSFileReadNoSuchFileError
                ? "not_found"
                : "io_error"
            result(FlutterError(code: code, message: error.localizedDescription, details: nil))
        } catch {
            result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
        }
    }

    private static func wantsAlbumAccess(from call: FlutterMethodCall) -> Bool {
        (call.arguments as? [String: Any])?["forAlbum"] as? Bool ?? false
    }

    private static func currentStatus(forAlbum: Bool) -> PHAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return PHPhotoLibrary.authorizationStatus(for: forAlbum ? .readWrite : .addOnly)
        }
        return PHPhotoLibrary.authorizationStatus()
    }

    private static func wireName(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "granted"
        case .restricted:
            return "restricted"
        case .denied:
            return "permanentlyDenied"
        case .notDetermined:
            return "denied"
        default:
            if #available(iOS 14.0, *), status == .limited {
                return "limited"
            }
            return "denied"
        }
    }

    private static func requestAccess(
        forAlbum: Bool,
        completion: @escaping (PHAuthorizationStatus) -> Void
    ) {
        let apply = {
            if #available(iOS 14.0, *) {
                PHPhotoLibrary.requestAuthorization(for: forAlbum ? .readWrite : .addOnly) {
                    newStatus in
                    DispatchQueue.main.async {
                        completion(newStatus)
                    }
                }
            } else {
                PHPhotoLibrary.requestAuthorization { newStatus in
                    DispatchQueue.main.async {
                        completion(newStatus)
                    }
                }
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func prepareFileURL(
        fileName: String,
        bytes: Data?,
        sourcePath: String?
    ) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_gallery_\(UUID().uuidString)_\(fileName)")
        if let bytes = bytes {
            try bytes.write(to: temp, options: .atomic)
            return temp
        }
        let source = URL(fileURLWithPath: sourcePath!)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoSuchFileError,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(sourcePath!)"]
            )
        }
        try FileManager.default.copyItem(at: source, to: temp)
        return temp
    }

    private static func fetchAlbum(named albumName: String) -> PHAssetCollection? {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var existing: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == albumName {
                existing = collection
                stop.pointee = true
            }
        }
        return existing
    }

    private static func performSave(
        fileURL: URL,
        createdTemp: Bool,
        isVideo: Bool,
        albumName: String?,
        existingAlbum: PHAssetCollection?,
        result: @escaping FlutterResult
    ) {
        var localIdentifier: String?
        PHPhotoLibrary.shared().performChanges({
            let request: PHAssetChangeRequest?
            if isVideo {
                request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
            guard let request = request,
                  let placeholder = request.placeholderForCreatedAsset
            else {
                return
            }
            localIdentifier = placeholder.localIdentifier
            if let albumName = albumName {
                add(placeholder, toAlbumNamed: albumName, existingAlbum: existingAlbum)
            }
        }, completionHandler: { success, error in
            if createdTemp {
                try? FileManager.default.removeItem(at: fileURL)
            }
            DispatchQueue.main.async {
                if let error = error {
                    result(flutterError(from: error))
                    return
                }
                guard success, let localIdentifier = localIdentifier else {
                    result(FlutterError(
                        code: "io_error",
                        message: "Unable to save media to the photo library",
                        details: nil
                    ))
                    return
                }
                result([
                    "name": fileURL.lastPathComponent,
                    "path": NSNull(),
                    "identifier": localIdentifier,
                ] as [String: Any])
            }
        })
    }

    private static func flutterError(from error: Error) -> FlutterError {
        let nsError = error as NSError
        // PHPhotosError.accessRestricted (3310) / accessUserDenied (3311)
        if nsError.domain == PHPhotosError.errorDomain &&
            (nsError.code == 3310 || nsError.code == 3311)
        {
            return FlutterError(
                code: "permission_denied",
                message: nsError.localizedDescription,
                details: nil
            )
        }
        return FlutterError(
            code: "io_error",
            message: nsError.localizedDescription,
            details: nil
        )
    }

    private static func add(
        _ placeholder: PHObjectPlaceholder,
        toAlbumNamed albumName: String,
        existingAlbum: PHAssetCollection?
    ) {
        if let existingAlbum = existingAlbum,
           let albumChange = PHAssetCollectionChangeRequest(for: existingAlbum)
        {
            albumChange.addAssets([placeholder] as NSArray)
        } else {
            let albumChange = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: albumName)
            albumChange.addAssets([placeholder] as NSArray)
        }
    }

    private static func cleanupTempIfNeeded(_ fileURL: URL, sourcePath: String?) {
        if fileURL.path != sourcePath {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
