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

/// Manages PhotoKit album queries, thumbnail caching, and asset-to-file export
/// (including iCloud network download support).
/// 负责 PhotoKit 相册与资源查询、缩略图缓存及所选资源导出（支持 iCloud 按需下载）。
final class PhotoLibraryRepository {

    let imageManager = PHCachingImageManager()

    /// Builds virtual ("All Media", "All Videos") and real PhotoKit albums.
    /// 查询并组装虚拟聚合相册（所有媒体、所有视频）与设备相册列表。
    func loadAlbums(mediaType: String, strings: CustomMediaPickerStrings) -> [MediaAlbumItem] {
        var albums: [MediaAlbumItem] = []

        // 1. All matching media / 全部符合类型条件的媒体
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

        // 2. All videos virtual album (only when picking mixed media)
        // “所有视频”虚拟相册（仅在混合选择图片与视频时显示）
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

        // 3. Smart albums & user albums / 智能相册与用户自建相册
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

    /// Exports selected [PHAsset] items to the plugin temporary cache directory
    /// and returns Flutter wire maps.
    /// 将选中的 [PHAsset] 导出到插件临时缓存目录并组装为 Flutter 通道 Map 列表。
    func exportAssets(
        _ assets: [PHAsset],
        withData: Bool,
        completion: @escaping ([[String: Any?]], Error?) -> Void
    ) {
        let group = DispatchGroup()
        var maps = [[String: Any?]?](repeating: nil, count: assets.count)
        var firstError: Error?
        let lock = NSLock()

        for (index, asset) in assets.enumerated() {
            group.enter()
            exportSingleAsset(asset, withData: withData) { map, error in
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

    private func exportSingleAsset(
        _ asset: PHAsset,
        withData: Bool,
        completion: @escaping ([String: Any?]?, Error?) -> Void
    ) {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredResource: PHAssetResource?
        if asset.mediaType == .video {
            preferredResource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo })
                ?? resources.first
        } else {
            preferredResource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto })
                ?? resources.first
        }

        guard let resource = preferredResource else {
            completion(nil, NSError(
                domain: "xue_hua_file_operations",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No asset resource available"]
            ))
            return
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            completion(nil, error)
            return
        }

        let fileName = resource.originalFilename.isEmpty
            ? (asset.mediaType == .video ? "video.mov" : "image.jpg")
            : resource.originalFilename
        let destURL = cacheDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")

        let writeOptions = PHAssetResourceRequestOptions()
        writeOptions.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: destURL, options: writeOptions) { error in
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

    /// Formats video duration in seconds as `m:ss` or `h:mm:ss`.
    /// 将视频秒级时长格式化为 `m:ss` 或 `h:mm:ss`。
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

    /// Formats a creation [Date] into a localized Month + Year label for the
    /// fast-scroll date bubble (e.g. "十一月 2026" / "November 2026").
    /// 将创建时间格式化为本地化“月份 + 年份”字符串，用于右侧快滑日期浮窗。
    static func formatMonthYear(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
