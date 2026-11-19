import AVFoundation
import Flutter
import Photos
import UIKit
import UniformTypeIdentifiers

/// Represents a virtual or PhotoKit album entry in the album dropdown.
/// 相册下拉浮窗中的虚拟聚合相册或 PhotoKit 相册分组项。
struct MediaAlbumItem {
    let id: String
    let title: String
    let fetchResult: PHFetchResult<PHAsset>
    let isAllMedia: Bool
    let isAllVideos: Bool

    var count: Int { fetchResult.count }
    var coverAsset: PHAsset? { fetchResult.firstObject }

    static let allMediaId = "__all_media__"
    static let allVideosId = "__all_videos__"
}

/// Manages PhotoKit album queries, thumbnail caching, and fully off-main-thread
/// asset export (including iCloud downloads and edited media support).
/// 负责 PhotoKit 相册查询、缩略图缓存及全异步后台导出（支持 iCloud 与已编辑媒体，绝不阻塞主线程）。
final class PhotoLibraryRepository {

    let imageManager = PHCachingImageManager()

    /// Builds virtual ("All Media", "All Videos") and real PhotoKit albums.
    /// 查询并组装虚拟聚合相册（所有媒体、所有视频）与设备相册列表。
    func loadAlbums(mediaType: String, strings: CustomMediaPickerStrings) -> [MediaAlbumItem] {
        var albums: [MediaAlbumItem] = []

        let allOptions = makeFetchOptions(mediaType: mediaType)
        let allAssets = PHAsset.fetchAssets(with: allOptions)
        albums.append(
            MediaAlbumItem(
                id: MediaAlbumItem.allMediaId,
                title: strings.allMedia,
                fetchResult: allAssets,
                isAllMedia: true,
                isAllVideos: false
            )
        )

        if mediaType == "media" {
            let videoAssets = PHAsset.fetchAssets(with: makeFetchOptions(mediaType: "video"))
            if videoAssets.count > 0 {
                albums.append(
                    MediaAlbumItem(
                        id: MediaAlbumItem.allVideosId,
                        title: strings.allVideos,
                        fetchResult: videoAssets,
                        isAllMedia: false,
                        isAllVideos: true
                    )
                )
            }
        }

        var seenIds = Set<String>()
        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumLivePhotos,
            .smartAlbumRecentlyAdded,
        ]
        for subtype in smartSubtypes {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            collections.enumerateObjects { collection, _, _ in
                guard !seenIds.contains(collection.localIdentifier) else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: self.makeFetchOptions(mediaType: mediaType))
                guard assets.count > 0 else { return }
                seenIds.insert(collection.localIdentifier)
                albums.append(
                    MediaAlbumItem(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Album",
                        fetchResult: assets,
                        isAllMedia: false,
                        isAllVideos: false
                    )
                )
            }
        }

        let userCollections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userCollections.enumerateObjects { collection, _, _ in
            guard !seenIds.contains(collection.localIdentifier) else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: self.makeFetchOptions(mediaType: mediaType))
            guard assets.count > 0 else { return }
            seenIds.insert(collection.localIdentifier)
            albums.append(
                MediaAlbumItem(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Album",
                    fetchResult: assets,
                    isAllMedia: false,
                    isAllVideos: false
                )
            )
        }

        return albums
    }

    private func makeFetchOptions(mediaType: String) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch mediaType {
        case "image":
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case "video":
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        default:
            options.predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
        }
        return options
    }

    /// Requests a fast grid thumbnail for a [PHAsset].
    /// 为网格单元格异步加载缩略图。
    @discardableResult
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// Exports selected [PHAsset] items completely off the main thread into the
    /// plugin temporary cache directory and invokes [completion] on the main queue.
    /// 在后台队列异步导出所选 [PHAsset] 到插件临时缓存目录，完成后回到主线程回调。
    func exportAssets(
        _ assets: [PHAsset],
        withData: Bool,
        completion: @escaping ([[String: Any?]], Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            var maps = [[String: Any?]?](repeating: nil, count: assets.count)
            var firstError: Error?
            let lock = NSLock()

            for (index, asset) in assets.enumerated() {
                group.enter()
                self.exportSingleAsset(asset, withData: withData) { map, error in
                    lock.lock()
                    if let map = map {
                        maps[index] = map
                    } else if firstError == nil {
                        firstError = error ?? NSError(
                            domain: "xue_hua_file_operations",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to export selected media"]
                        )
                    }
                    lock.unlock()
                    group.leave()
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
    }

    private func exportSingleAsset(
        _ asset: PHAsset,
        withData: Bool,
        completion: @escaping ([String: Any?]?, Error?) -> Void
    ) {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            completion(nil, error)
            return
        }

        if asset.mediaType == .image {
            exportImageAsset(asset, cacheDir: cacheDir, withData: withData, completion: completion)
        } else {
            exportVideoAsset(asset, cacheDir: cacheDir, withData: withData, completion: completion)
        }
    }

    /// Uses [PHImageManager.requestImageDataAndOrientation] for fast, reliable
    /// image export without main-thread stalls or PHAssetResource hangs.
    /// 使用 [PHImageManager.requestImageDataAndOrientation] 高效导出图片，避免资源流挂起。
    private func exportImageAsset(
        _ asset: PHAsset,
        cacheDir: URL,
        withData: Bool,
        completion: @escaping ([String: Any?]?, Error?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, info in
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = data {
                    let ext: String
                    if let uti = dataUTI, let type = UTType(uti), let preferred = type.preferredFilenameExtension {
                        ext = preferred
                    } else {
                        ext = "jpg"
                    }
                    let fileName = "IMG_\(UUID().uuidString.prefix(8)).\(ext)"
                    let destURL = cacheDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
                    do {
                        try data.write(to: destURL, options: .atomic)
                        let bytes = withData ? FlutterStandardTypedData(bytes: data) : nil
                        completion([
                            "name": fileName,
                            "size": data.count,
                            "path": destURL.path,
                            "bytes": bytes,
                            "identifier": asset.localIdentifier,
                        ], nil)
                    } catch {
                        completion(nil, error)
                    }
                    return
                }
                let err = (info?[PHImageErrorKey] as? Error) ?? NSError(
                    domain: "xue_hua_file_operations",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to read image data"]
                )
                completion(nil, err)
            }
        }
    }

    /// Exports video assets off-main-thread via [PHImageManager.requestAVAsset]
    /// (fast file copy for [AVURLAsset]), falling back to [PHAssetResourceManager].
    /// 在后台线程优先通过 [AVURLAsset] 快速拷贝视频文件，异常时回退至 [PHAssetResourceManager]。
    private func exportVideoAsset(
        _ asset: PHAsset,
        cacheDir: URL,
        withData: Bool,
        completion: @escaping ([String: Any?]?, Error?) -> Void
    ) {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            DispatchQueue.global(qos: .userInitiated).async {
                if let urlAsset = avAsset as? AVURLAsset {
                    let fileName = urlAsset.url.lastPathComponent.isEmpty
                        ? "VID_\(UUID().uuidString.prefix(8)).mov"
                        : urlAsset.url.lastPathComponent
                    let destURL = cacheDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: urlAsset.url, to: destURL)
                        var size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                        var bytes: FlutterStandardTypedData?
                        if withData {
                            let data = try Data(contentsOf: destURL)
                            bytes = FlutterStandardTypedData(bytes: data)
                            size = data.count
                        }
                        completion([
                            "name": fileName,
                            "size": size,
                            "path": destURL.path,
                            "bytes": bytes,
                            "identifier": asset.localIdentifier,
                        ], nil)
                        return
                    } catch {
                        // Fall through to resource manager fallback / 回退到资源流导出
                    }
                }

                let resources = PHAssetResource.assetResources(for: asset)
                guard let resource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo })
                        ?? resources.first else {
                    let err = (info?[PHImageErrorKey] as? Error) ?? NSError(
                        domain: "xue_hua_file_operations",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "No video resource available"]
                    )
                    completion(nil, err)
                    return
                }
                let fileName = resource.originalFilename.isEmpty ? "video.mov" : resource.originalFilename
                let destURL = cacheDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
                let writeOptions = PHAssetResourceRequestOptions()
                writeOptions.isNetworkAccessAllowed = true
                PHAssetResourceManager.default().writeData(for: resource, toFile: destURL, options: writeOptions) { error in
                    DispatchQueue.global(qos: .userInitiated).async {
                        if let error = error {
                            completion(nil, error)
                            return
                        }
                        do {
                            var size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                            var bytes: FlutterStandardTypedData?
                            if withData {
                                let data = try Data(contentsOf: destURL)
                                bytes = FlutterStandardTypedData(bytes: data)
                                size = data.count
                            }
                            completion([
                                "name": fileName,
                                "size": size,
                                "path": destURL.path,
                                "bytes": bytes,
                                "identifier": asset.localIdentifier,
                            ], nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func formatMonthYear(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
