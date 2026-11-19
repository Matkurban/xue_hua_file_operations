import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

import '../test_env_stub.dart' if (dart.library.io) '../test_env_io.dart'
    as test_env;

/// Preset accent color entry for the custom media picker demo.
/// 自定义媒体选择器演示用的强调色预设项。
class PickerAccentPreset {
  const PickerAccentPreset({required this.label, required this.color});

  final String label;
  final Color color;
}

/// Reactive state controller for the example app, managing all plugin options,
/// picked files, directory results, and async actions without `setState`.
/// 示例应用的响应式状态控制器，统一管理插件选项、已选文件、目录结果与异步操作（不使用 `setState`）。
class FileOperationsController extends ChangeNotifier {
  FileOperationsController({XueHuaFileOperations? ops})
    : _ops = ops ?? XueHuaFileOperations.instance;

  final XueHuaFileOperations _ops;

  static const List<PickerAccentPreset> accentPresets = [
    PickerAccentPreset(label: 'Sky Blue', color: Color(0xFF2AABEE)),
    PickerAccentPreset(label: 'Indigo', color: Color(0xFF5856D6)),
    PickerAccentPreset(label: 'Emerald', color: Color(0xFF10B981)),
    PickerAccentPreset(label: 'Coral', color: Color(0xFFEF4444)),
  ];

  bool _withData = false;
  int? _maxFiles;
  FileType _pickType = FileType.any;
  MediaPickerMode _pickerMode = MediaPickerMode.system;
  bool _showCameraTile = true;
  bool _enablePreview = true;
  bool _initialExpanded = false;
  bool _allowOpenInOtherApp = true;
  Color _accentColor = const Color(0xFF2AABEE);
  CameraFacing _camera = CameraFacing.rear;

  String _status = 'Ready';
  List<PlatformFile> _files = const [];
  DirectoryResult? _directory;
  PlatformFile? _selected;

  bool get withData => _withData;
  int? get maxFiles => _maxFiles;
  FileType get pickType => _pickType;
  MediaPickerMode get pickerMode => _pickerMode;
  bool get showCameraTile => _showCameraTile;
  bool get enablePreview => _enablePreview;
  bool get initialExpanded => _initialExpanded;
  bool get allowOpenInOtherApp => _allowOpenInOtherApp;
  Color get accentColor => _accentColor;
  CameraFacing get camera => _camera;

  String get status => _status;
  List<PlatformFile> get files => _files;
  DirectoryResult? get directory => _directory;
  PlatformFile? get selected => _selected;

  bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Builds [MediaPickerOptions] when custom mode is enabled; returns `null`
  /// in system mode to exercise the default code path.
  /// 自定义模式下构建 [MediaPickerOptions]；系统模式下返回 `null` 以验证默认路径。
  MediaPickerOptions? get mediaPickerOptions {
    if (_pickerMode == MediaPickerMode.system) return null;
    return MediaPickerOptions(
      mode: MediaPickerMode.custom,
      showCameraTile: _showCameraTile,
      allowOpenInOtherApp: _allowOpenInOtherApp,
      initialExpanded: _initialExpanded,
      enablePreview: _enablePreview,
      theme: MediaPickerTheme(primaryColor: _accentColor),
    );
  }

  void setWithData(bool value) {
    if (_withData == value) return;
    _withData = value;
    notifyListeners();
  }

  void setLimitMaxFiles(bool enabled) {
    final next = enabled ? 3 : null;
    if (_maxFiles == next) return;
    _maxFiles = next;
    notifyListeners();
  }

  void setPickType(FileType type) {
    if (_pickType == type) return;
    _pickType = type;
    notifyListeners();
  }

  void setPickerMode(MediaPickerMode mode) {
    if (_pickerMode == mode) return;
    _pickerMode = mode;
    // Automatically switch `any` -> `media` when turning on Custom Picker so
    // tapping Pick File / Pick Files immediately opens the custom media sheet.
    // 切换至自定义选择器时，若当前过滤类型为 `any`，自动切到 `media` 以便直接体验。
    if (_pickerMode == MediaPickerMode.custom && _pickType == FileType.any) {
      _pickType = FileType.media;
    }
    notifyListeners();
  }

  void setShowCameraTile(bool value) {
    if (_showCameraTile == value) return;
    _showCameraTile = value;
    notifyListeners();
  }

  void setEnablePreview(bool value) {
    if (_enablePreview == value) return;
    _enablePreview = value;
    notifyListeners();
  }

  void setInitialExpanded(bool value) {
    if (_initialExpanded == value) return;
    _initialExpanded = value;
    notifyListeners();
  }

  void setAllowOpenInOtherApp(bool value) {
    if (_allowOpenInOtherApp == value) return;
    _allowOpenInOtherApp = value;
    notifyListeners();
  }

  void setAccentColor(Color color) {
    if (_accentColor == color) return;
    _accentColor = color;
    notifyListeners();
  }

  void setCameraFacing(CameraFacing facing) {
    if (_camera == facing) return;
    _camera = facing;
    notifyListeners();
  }

  void selectFile(PlatformFile file) {
    _selected = file;
    notifyListeners();
  }

  void clearResults() {
    _files = const [];
    _directory = null;
    _selected = null;
    _status = 'Ready';
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FileOperationsException catch (e) {
      _status = e.toString();
      notifyListeners();
    } catch (e) {
      _status = 'Error: $e';
      notifyListeners();
    }
  }

  void _applyCaptured(PlatformFile? file, String label) {
    if (file == null) {
      _status = 'Cancelled';
    } else {
      _files = [file];
      _selected = file;
      _status = '$label captured';
    }
    notifyListeners();
  }

  Future<void> pickFile() => _run(() async {
    final file = await _ops.pickFile(
      withData: _withData,
      type: _pickType,
      mediaPickerOptions: mediaPickerOptions,
    );
    if (file == null) {
      _status = 'Cancelled';
    } else {
      _files = [file];
      _selected = file;
      _status = 'Picked 1 file';
    }
    notifyListeners();
  });

  Future<void> pickFiles() => _run(() async {
    final picked = await _ops.pickFiles(
      withData: _withData,
      maxFiles: _maxFiles,
      type: _pickType,
      mediaPickerOptions: mediaPickerOptions,
    );
    if (picked == null) {
      _status = 'Cancelled';
    } else {
      _files = picked;
      _selected = picked.isNotEmpty ? picked.first : null;
      _status = 'Picked ${picked.length} file(s)';
    }
    notifyListeners();
  });

  Future<void> capturePhoto() => _run(() async {
    final file = await _ops.capturePhoto(
      preferredCamera: _camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
      withData: _withData,
    );
    _applyCaptured(file, 'Photo');
  });

  Future<void> captureVideo() => _run(() async {
    final file = await _ops.captureVideo(
      preferredCamera: _camera,
      maxDuration: const Duration(seconds: 30),
      withData: _withData,
    );
    _applyCaptured(file, 'Video');
  });

  Future<void> retrieveLostCapture() => _run(() async {
    final lost = await _ops.retrieveLostCapture();
    if (lost.isEmpty) {
      _status = 'No lost capture';
    } else {
      _files = lost.files;
      _selected = lost.files.isEmpty ? null : lost.files.first;
      _status =
          'Recovered lost ${lost.type?.name ?? "capture"}'
          '${lost.exception != null ? " (${lost.exception})" : ""}';
    }
    notifyListeners();
  });

  Future<void> pickDirectory() => _run(() async {
    final dir = await _ops.pickDirectory();
    if (dir == null) {
      _status = 'Cancelled';
    } else {
      _directory = dir;
      _status = 'Directory: ${dir.path}';
    }
    notifyListeners();
  });

  Future<void> saveFile() => _run(() async {
    final source = _selected;
    final path = source?.path;
    final bytes = source?.bytes;
    final Uint8List? saveBytes;
    final String? saveSourcePath;

    if (path != null && path.isNotEmpty) {
      saveBytes = null;
      saveSourcePath = path;
    } else if (bytes != null) {
      saveBytes = bytes;
      saveSourcePath = null;
    } else {
      saveBytes = Uint8List.fromList(
        'Hello from XueHuaFileOperations\n'.codeUnits,
      );
      saveSourcePath = null;
    }

    final result = await _ops.saveFile(
      fileName: source?.name ?? 'xue_hua_export.txt',
      bytes: saveBytes,
      sourcePath: saveSourcePath,
    );
    _status = result == null
        ? 'Cancelled'
        : 'Saved: ${result.path ?? result.name}';
    notifyListeners();
  });

  Future<void> saveToGallery(BuildContext context) => _run(() async {
    final source = _selected;
    if (source == null) {
      _status = 'Select a file first';
      notifyListeners();
      return;
    }
    final path = source.path;
    final bytes = source.bytes;
    final Uint8List? saveBytes;
    final String? saveSourcePath;
    if (path != null && path.isNotEmpty) {
      saveBytes = null;
      saveSourcePath = path;
    } else if (bytes != null) {
      saveBytes = bytes;
      saveSourcePath = null;
    } else {
      _status = 'Selected file has no path or bytes to save';
      notifyListeners();
      return;
    }

    try {
      final result = await _ops.saveToGallery(
        fileName: source.name,
        bytes: saveBytes,
        sourcePath: saveSourcePath,
      );
      _status = 'Gallery: ${result.path ?? result.identifier ?? result.name}';
      notifyListeners();
    } on FileOperationsException catch (e) {
      _status = e.toString();
      notifyListeners();
      if (e.code == ErrorCode.permissionDenied && context.mounted) {
        await _offerOpenSettings(
          context,
          _isMacOS
              ? 'Photo library access was denied. If System Settings -> Photos '
                    'is empty, quit and launch this app from Terminal or the '
                    '.app (not from Cursor/VS Code), then try again.'
              : 'Photo library access was denied. The system will not ask again; '
                    'enable Photos for this app in Settings.',
        );
      }
    }
  });

  Future<void> checkGalleryStatus() => _run(() async {
    final result = await _ops.galleryPermissionStatus();
    _status = _describeGalleryStatus(result, requested: false);
    notifyListeners();
  });

  Future<void> requestGalleryPermission(BuildContext context) => _run(() async {
    final result = await _ops.requestGalleryPermission();
    _status = _describeGalleryStatus(result, requested: true);
    notifyListeners();
    if ((result.isPermanentlyDenied || result.isRestricted) &&
        context.mounted) {
      await _offerOpenSettings(
        context,
        result.isRestricted
            ? 'Photos access is restricted (for example by parental controls). '
                  'It cannot be changed from a permission dialog.'
            : _permanentlyDeniedMessage(),
      );
    }
  });

  Future<void> openSelected() => _run(() async {
    final file = _selected;
    if (file == null) {
      _status = 'Select a file first';
      notifyListeners();
      return;
    }
    await _ops.openFile(path: file.path, identifier: file.identifier);
    _status = 'Opened ${file.name}';
    notifyListeners();
  });

  String _describeGalleryStatus(
    GalleryPermissionStatus result, {
    required bool requested,
  }) {
    final prefix = requested ? 'Gallery permission' : 'Gallery status';
    switch (result) {
      case GalleryPermissionStatus.denied:
        return '$prefix: denied (not determined yet; Request can still show a system dialog)';
      case GalleryPermissionStatus.permanentlyDenied:
        return '$prefix: permanentlyDenied (no system dialog; '
            '${_isMacOS ? 'launch from Terminal or the .app, then retry' : 'use Open Settings'})';
      case GalleryPermissionStatus.restricted:
        return '$prefix: restricted (OS blocked Photos access)';
      default:
        return '$prefix: ${result.name}';
    }
  }

  String _permanentlyDeniedMessage() {
    if (_isMacOS) {
      return 'The system will not show the Photos prompt again from this '
          'launch. If System Settings -> Photos is empty, quit this app and '
          'start it from Terminal (`flutter run -d macos`) or by opening the '
          '.app, then request permission again.';
    }
    return 'The system will not show the Photos prompt again. '
        'Enable Photos for this app in Settings.';
  }

  Future<void> _offerOpenSettings(BuildContext context, String message) async {
    if (!context.mounted || test_env.hasAutomatedTestEnv) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Photos permission'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (open == true) {
      await _ops.openAppSettings();
    }
  }
}
