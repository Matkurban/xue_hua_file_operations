import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

/// Displays picked directory metadata and the list of selected files.
/// 展示已选目录信息与所选文件列表的结果区组件。
class ResultsSection extends StatelessWidget {
  const ResultsSection({
    super.key,
    required this.directory,
    required this.files,
    required this.selected,
    required this.onSelectFile,
  });

  final DirectoryResult? directory;
  final List<PlatformFile> files;
  final PlatformFile? selected;
  final ValueChanged<PlatformFile> onSelectFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (directory != null) ...[
          Text(
            'Directory',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(directory!.name),
              subtitle: Text(
                key: const ValueKey('directory_info'),
                '${directory!.name}\n${directory!.path}',
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Files (${files.length})',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (files.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No files selected')),
            ),
          )
        else
          for (var i = 0; i < files.length; i++)
            _PickedFileCard(
              index: i,
              file: files[i],
              isSelected:
                  identical(files[i], selected) ||
                  (files[i].path != null && files[i].path == selected?.path) ||
                  (files[i].identifier != null &&
                      files[i].identifier == selected?.identifier),
              onTap: () => onSelectFile(files[i]),
            ),
      ],
    );
  }
}

class _PickedFileCard extends StatelessWidget {
  const _PickedFileCard({
    required this.index,
    required this.file,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final PlatformFile file;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('file_$index'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        selected: isSelected,
        leading: Icon(
          isSelected
              ? Icons.check_circle_rounded
              : Icons.insert_drive_file_outlined,
        ),
        title: Text(file.name, key: ValueKey('file_name_$index')),
        subtitle: Text(
          key: ValueKey('file_info_$index'),
          'size=${file.size}\n'
          'path=${file.path ?? "(null)"}\n'
          'hasBytes=${file.hasBytes}\n'
          'id=${file.identifier ?? "(null)"}',
        ),
        onTap: onTap,
      ),
    );
  }
}
