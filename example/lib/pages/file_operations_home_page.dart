import 'package:material_ui/material_ui.dart';

import '../controllers/file_operations_controller.dart';
import '../widgets/actions_section.dart';
import '../widgets/picker_options_section.dart';
import '../widgets/results_section.dart';
import '../widgets/status_banner_card.dart';

/// Main demo page composing modular status, options, actions, and results
/// sections driven by [FileOperationsController].
/// 主演示页面：由 [FileOperationsController] 驱动，组合状态栏、选项配置、操作按钮与结果展示模块。
class FileOperationsHomePage extends StatefulWidget {
  const FileOperationsHomePage({super.key});

  @override
  State<FileOperationsHomePage> createState() => _FileOperationsHomePageState();
}

class _FileOperationsHomePageState extends State<FileOperationsHomePage> {
  final FileOperationsController _controller = FileOperationsController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XueHua File Operations')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  StatusBannerCard(
                    status: _controller.status,
                    fileCount: _controller.files.length,
                    hasDirectory: _controller.directory != null,
                    onClear: _controller.clearResults,
                  ),
                  const SizedBox(height: 12),
                  PickerOptionsSection(controller: _controller),
                  const SizedBox(height: 12),
                  ActionsSection(controller: _controller),
                  const SizedBox(height: 16),
                  ResultsSection(
                    directory: _controller.directory,
                    files: _controller.files,
                    selected: _controller.selected,
                    onSelectFile: _controller.selectFile,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
