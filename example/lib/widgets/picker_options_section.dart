import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

import '../controllers/file_operations_controller.dart';

/// Configuration card for file-picking filters, camera facing, and mobile
/// custom media picker theme/behavior toggles.
/// 文件筛选条件、摄像头方向及移动端自定义媒体选择器主题与行为配置卡片。
class PickerOptionsSection extends StatelessWidget {
  const PickerOptionsSection({super.key, required this.controller});

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
              'Picker & Camera Options',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('withData'),
              contentPadding: EdgeInsets.zero,
              title: const Text('withData'),
              subtitle: const Text('Load bytes into memory (always on Web)'),
              value: controller.withData,
              onChanged: controller.setWithData,
            ),
            SwitchListTile(
              key: const ValueKey('limitMaxFiles'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Limit maxFiles to 3'),
              value: controller.maxFiles != null,
              onChanged: controller.setLimitMaxFiles,
            ),
            const SizedBox(height: 8),
            Text(
              'FileType Filter',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<FileType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: FileType.any, label: Text('any')),
                  ButtonSegment(value: FileType.media, label: Text('media')),
                  ButtonSegment(value: FileType.image, label: Text('image')),
                  ButtonSegment(value: FileType.video, label: Text('video')),
                ],
                selected: {controller.pickType},
                onSelectionChanged: (s) => controller.setPickType(s.first),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Mobile Media Picker Mode',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<MediaPickerMode>(
                key: const ValueKey('mediaPickerMode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MediaPickerMode.system,
                    label: Text('System Picker'),
                  ),
                  ButtonSegment(
                    value: MediaPickerMode.custom,
                    label: Text('Custom Picker'),
                  ),
                ],
                selected: {controller.pickerMode},
                onSelectionChanged: (s) => controller.setPickerMode(s.first),
              ),
            ),
            if (controller.pickerMode == MediaPickerMode.custom) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('showCameraTile'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show live camera tile'),
                value: controller.showCameraTile,
                onChanged: controller.setShowCameraTile,
              ),
              SwitchListTile(
                key: const ValueKey('enablePreview'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable full-screen preview'),
                value: controller.enablePreview,
                onChanged: controller.setEnablePreview,
              ),
              SwitchListTile(
                key: const ValueKey('initialExpanded'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Open fullscreen initially'),
                value: controller.initialExpanded,
                onChanged: controller.setInitialExpanded,
              ),
              SwitchListTile(
                key: const ValueKey('allowOpenInOtherApp'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow "Open in other app"'),
                value: controller.allowOpenInOtherApp,
                onChanged: controller.setAllowOpenInOtherApp,
              ),
              const SizedBox(height: 6),
              Text(
                'Custom Picker Accent Color',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in FileOperationsController.accentPresets)
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: preset.color,
                        radius: 8,
                      ),
                      label: Text(preset.label),
                      selected: controller.accentColor == preset.color,
                      onSelected: (_) =>
                          controller.setAccentColor(preset.color),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Preferred Camera',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<CameraFacing>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CameraFacing.rear,
                    label: Text('Rear Camera'),
                  ),
                  ButtonSegment(
                    value: CameraFacing.front,
                    label: Text('Front Camera'),
                  ),
                ],
                selected: {controller.camera},
                onSelectionChanged: (s) => controller.setCameraFacing(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
