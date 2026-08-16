import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XueHua File Operations',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const FileOperationsDemoPage(),
    );
  }
}

class FileOperationsDemoPage extends StatefulWidget {
  const FileOperationsDemoPage({super.key});

  @override
  State<FileOperationsDemoPage> createState() => _FileOperationsDemoPageState();
}

class _FileOperationsDemoPageState extends State<FileOperationsDemoPage> {
  final _ops = XueHuaFileOperations.instance;

  bool _withData = false;
  int? _maxFiles;
  String _status = 'Ready';
  List<PlatformFile> _files = const [];
  DirectoryResult? _directory;
  PlatformFile? _selected;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FileOperationsException catch (e) {
      setState(() => _status = e.toString());
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _pickFile() => _run(() async {
    final file = await _ops.pickFile(withData: _withData);
    if (!mounted) return;
    if (file == null) {
      setState(() => _status = 'Cancelled');
      return;
    }
    setState(() {
      _files = [file];
      _selected = file;
      _status = 'Picked 1 file';
    });
  });

  Future<void> _pickFiles() => _run(() async {
    final files = await _ops.pickFiles(
      withData: _withData,
      maxFiles: _maxFiles,
    );
    if (!mounted) return;
    if (files == null) {
      setState(() => _status = 'Cancelled');
      return;
    }
    setState(() {
      _files = files;
      _selected = files.isNotEmpty ? files.first : null;
      _status = 'Picked ${files.length} file(s)';
    });
  });

  Future<void> _pickDirectory() => _run(() async {
    final dir = await _ops.pickDirectory();
    if (!mounted) return;
    if (dir == null) {
      setState(() => _status = 'Cancelled');
      return;
    }
    setState(() {
      _directory = dir;
      _status = 'Directory: ${dir.path}';
    });
  });

  Future<void> _saveFile() => _run(() async {
    final source = _selected;
    final path = source?.path;
    final bytes = source?.bytes;
    final Uint8List? saveBytes;
    final String? saveSourcePath;

    if (path != null && path.isNotEmpty) {
      // Prefer copying from path so withData:false still saves full content.
      saveBytes = null;
      saveSourcePath = path;
    } else if (bytes != null) {
      saveBytes = bytes;
      saveSourcePath = null;
    } else {
      // Demo fallback when nothing is selected.
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
    if (!mounted) return;
    if (result == null) {
      setState(() => _status = 'Cancelled');
      return;
    }
    setState(() {
      _status = 'Saved: ${result.path ?? result.name}';
    });
  });

  Future<void> _saveToGallery() => _run(() async {
    final source = _selected;
    if (source == null) {
      setState(() => _status = 'Select a file first');
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
      setState(() => _status = 'Selected file has no path or bytes to save');
      return;
    }

    try {
      final result = await _ops.saveToGallery(
        fileName: source.name,
        bytes: saveBytes,
        sourcePath: saveSourcePath,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Gallery: ${result.path ?? result.identifier ?? result.name}';
      });
    } on FileOperationsException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.toString());
      if (e.code == ErrorCode.permissionDenied) {
        await _offerOpenSettings(
          'Photo library access was denied. The system will not ask again; '
          'enable Photos for this app in Settings.',
        );
      }
    }
  });

  Future<void> _galleryStatus() => _run(() async {
    final status = await _ops.galleryPermissionStatus();
    if (!mounted) return;
    setState(() => _status = _describeGalleryStatus(status, requested: false));
  });

  Future<void> _requestGalleryPermission() => _run(() async {
    final status = await _ops.requestGalleryPermission();
    if (!mounted) return;
    setState(() => _status = _describeGalleryStatus(status, requested: true));
    if (status.isPermanentlyDenied || status.isRestricted) {
      await _offerOpenSettings(
        status.isRestricted
            ? 'Photos access is restricted (for example by parental controls). '
                  'It cannot be changed from a permission dialog.'
            : 'The system will not show the Photos prompt again. '
                  'Enable Photos for this app in Settings.',
      );
    }
  });

  String _describeGalleryStatus(
    GalleryPermissionStatus status, {
    required bool requested,
  }) {
    final prefix = requested ? 'Gallery permission' : 'Gallery status';
    switch (status) {
      case GalleryPermissionStatus.denied:
        return '$prefix: denied (not determined yet; Request can still show a system dialog)';
      case GalleryPermissionStatus.permanentlyDenied:
        return '$prefix: permanentlyDenied (no system dialog; use Open Settings)';
      case GalleryPermissionStatus.restricted:
        return '$prefix: restricted (OS blocked Photos access)';
      default:
        return '$prefix: ${status.name}';
    }
  }

  Future<void> _offerOpenSettings(String message) async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Photos permission'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
    if (open == true) {
      await _ops.openAppSettings();
    }
  }

  Future<void> _openSelected() => _run(() async {
    final file = _selected;
    if (file == null) {
      setState(() => _status = 'Select a file first');
      return;
    }
    // await _ops.openFile(path: file.path, identifier: file.identifier);
    await _ops.openFile(path: file.path);
    if (!mounted) return;
    setState(() => _status = 'Opened ${file.name}');
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XueHua File Operations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(
            _status,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('withData'),
            subtitle: const Text('Load bytes into memory (always on Web)'),
            value: _withData,
            onChanged: (v) => setState(() => _withData = v),
          ),
          SwitchListTile(
            title: const Text('Limit maxFiles to 3'),
            value: _maxFiles != null,
            onChanged: (v) => setState(() => _maxFiles = v ? 3 : null),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _pickFile,
                child: const Text('Pick File'),
              ),
              FilledButton.tonal(
                onPressed: _pickFiles,
                child: const Text('Pick Files'),
              ),
              OutlinedButton(
                onPressed: _pickDirectory,
                child: const Text('Pick Directory'),
              ),
              OutlinedButton(
                onPressed: _saveFile,
                child: const Text('Save As'),
              ),
              OutlinedButton(
                onPressed: _saveToGallery,
                child: const Text('Save to Gallery'),
              ),
              OutlinedButton(
                onPressed: _galleryStatus,
                child: const Text('Gallery Status'),
              ),
              OutlinedButton(
                onPressed: _requestGalleryPermission,
                child: const Text('Request Gallery Permission'),
              ),
              OutlinedButton(
                onPressed: _openSelected,
                child: const Text('Open Selected'),
              ),
            ],
          ),
          if (_directory != null) ...[
            const SizedBox(height: 16),
            Text('Directory', style: Theme.of(context).textTheme.titleSmall),
            Text('${_directory!.name}\n${_directory!.path}'),
          ],
          const SizedBox(height: 16),
          Text('Files', style: Theme.of(context).textTheme.titleSmall),
          if (_files.isEmpty)
            const Text('No files selected')
          else
            ..._files.map((file) {
              final selected =
                  identical(file, _selected) ||
                  (file.path != null && file.path == _selected?.path) ||
                  (file.identifier != null &&
                      file.identifier == _selected?.identifier);
              return Card(
                child: ListTile(
                  selected: selected,
                  title: Text(file.name),
                  subtitle: Text(
                    'size=${file.size}\n'
                    'path=${file.path ?? "(null)"}\n'
                    'hasBytes=${file.hasBytes}\n'
                    'id=${file.identifier ?? "(null)"}',
                  ),
                  onTap: () => setState(() => _selected = file),
                ),
              );
            }),
        ],
      ),
    );
  }
}
