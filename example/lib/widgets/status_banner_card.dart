import 'package:material_ui/material_ui.dart';

/// Displays the live operation status and quick summary of current selections.
/// 展示当前插件操作状态与已选文件/目录摘要的顶部状态卡片。
class StatusBannerCard extends StatelessWidget {
  const StatusBannerCard({
    super.key,
    required this.status,
    required this.fileCount,
    required this.hasDirectory,
    required this.onClear,
  });

  final String status;
  final int fileCount;
  final bool hasDirectory;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasAnyResult = fileCount > 0 || hasDirectory;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.info_outline_rounded,
                color: scheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    key: const ValueKey('status'),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (hasAnyResult)
              IconButton(
                tooltip: 'Clear results',
                onPressed: onClear,
                icon: const Icon(Icons.clear_all_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
