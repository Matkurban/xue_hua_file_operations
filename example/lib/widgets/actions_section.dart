import 'package:material_ui/material_ui.dart';

import '../controllers/file_operations_controller.dart';

/// Grouped action buttons covering file picking, camera capture, saving,
/// gallery permissions, and opening files.
/// 分组操作区卡片：涵盖文件/目录选择、相机拍摄、另存为与图库权限及文件打开操作。
class ActionsSection extends StatelessWidget {
  const ActionsSection({super.key, required this.controller});

  final FileOperationsController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('pickFile'),
                  onPressed: controller.pickFile,
                  icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
                  label: const Text('Pick File'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('pickFiles'),
                  onPressed: controller.pickFiles,
                  icon: const Icon(Icons.collections_outlined, size: 18),
                  label: const Text('Pick Files'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('capturePhoto'),
                  onPressed: controller.capturePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Take Photo'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('captureVideo'),
                  onPressed: controller.captureVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Record Video'),
                ),
                OutlinedButton(
                  key: const ValueKey('retrieveLostCapture'),
                  onPressed: controller.retrieveLostCapture,
                  child: const Text('Retrieve Lost Capture'),
                ),
                OutlinedButton(
                  key: const ValueKey('pickDirectory'),
                  onPressed: controller.pickDirectory,
                  child: const Text('Pick Directory'),
                ),
                OutlinedButton(
                  key: const ValueKey('saveFile'),
                  onPressed: controller.saveFile,
                  child: const Text('Save As'),
                ),
                OutlinedButton(
                  key: const ValueKey('saveToGallery'),
                  onPressed: () => controller.saveToGallery(context),
                  child: const Text('Save to Gallery'),
                ),
                OutlinedButton(
                  key: const ValueKey('galleryStatus'),
                  onPressed: controller.checkGalleryStatus,
                  child: const Text('Gallery Status'),
                ),
                OutlinedButton(
                  key: const ValueKey('requestGalleryPermission'),
                  onPressed: () => controller.requestGalleryPermission(context),
                  child: const Text('Request Gallery Permission'),
                ),
                OutlinedButton(
                  key: const ValueKey('openSelected'),
                  onPressed: controller.openSelected,
                  child: const Text('Open Selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
