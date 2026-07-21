import Flutter
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
    case "openFile":
      openFile(call: call, result: result)
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
    if !types.isEmpty { return types }

    switch args?["type"] as? String {
    case "image": return [.image]
    case "video": return [.movie]
    case "audio": return [.audio]
    default: return [.item]
    }
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

    let types: [UTType] = directory ? [.folder] : contentTypes(from: args)
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: !directory)
    picker.delegate = self
    picker.allowsMultipleSelection = multiple && !directory
    presenter.present(picker, animated: true)
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

    if flutterData == nil && (sourcePath == nil || sourcePath!.isEmpty) {
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

      let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
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

    let access = resolved.url.isFileURL
      ? resolved.url.startAccessingSecurityScopedResource()
      : false

    UIApplication.shared.open(resolved.url, options: [:]) { [weak self] success in
      if success {
        if access { resolved.url.stopAccessingSecurityScopedResource() }
        result(true)
        return
      }
      // Fallback: UIDocumentInteractionController preview/open-in menu.
      guard let self = self, let presenter = self.rootViewController() else {
        if access { resolved.url.stopAccessingSecurityScopedResource() }
        result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
        return
      }
      let controller = UIDocumentInteractionController(url: resolved.url)
      controller.delegate = self
      self.documentInteractionController = controller
      let presented = controller.presentPreview(animated: true)
        || controller.presentOpenInMenu(
          from: presenter.view.bounds,
          in: presenter.view,
          animated: true
        )
      if !presented {
        if access { resolved.url.stopAccessingSecurityScopedResource() }
        self.documentInteractionController = nil
        result(FlutterError(code: "io_error", message: "Unable to open file", details: nil))
      } else {
        // Keep security-scoped access until interaction ends; stop in delegate.
        if !access {
          // Nothing to retain for non-scoped URLs.
        }
        result(true)
      }
    }
  }

  public func documentInteractionControllerDidEndPreview(
    _ controller: UIDocumentInteractionController
  ) {
    controller.url?.stopAccessingSecurityScopedResource()
    documentInteractionController = nil
  }

  public func documentInteractionController(
    _ controller: UIDocumentInteractionController,
    willBeginSendingToApplication application: String?
  ) {
    // Keep access while sending; stop after dismiss via didDismissOpenInMenu if needed.
  }

  public func documentInteractionControllerDidDismissOpenInMenu(
    _ controller: UIDocumentInteractionController
  ) {
    controller.url?.stopAccessingSecurityScopedResource()
    documentInteractionController = nil
  }

  public func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
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
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let bookmark = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return Self.bookmarkPrefix + bookmark.base64EncodedString()
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingResult
    clearPending()
    result?(nil)
  }

  public func documentPicker(
    _ controller: UIDocumentPickerViewController,
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
      do {
        result(["file": try fileMap(from: url, withData: withData)])
      } catch {
        result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
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
      do {
        let files = try urls.map { try fileMap(from: $0, withData: withData) }
        result(["files": files])
      } catch {
        result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
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
          "identifier": identifier
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
        "name": fileName
      ])
    }
  }

  private func fileMap(from url: URL, withData: Bool) throws -> [String: Any?] {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
    let name = values.name ?? url.lastPathComponent
    var size = values.fileSize ?? 0
    var bytes: FlutterStandardTypedData?

    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("xue_hua_file_operations", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    let dest = cacheURL.appendingPathComponent(
      "\(Int(Date().timeIntervalSince1970 * 1000))_\(name)"
    )
    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.copyItem(at: url, to: dest)
    if size == 0 {
      size = (try dest.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
    }

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
      "identifier": url.absoluteString
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
