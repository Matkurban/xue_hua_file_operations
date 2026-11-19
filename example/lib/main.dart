import 'package:material_ui/material_ui.dart';

import 'pages/file_operations_home_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

/// Root widget for the `xue_hua_file_operations` example application.
/// `xue_hua_file_operations` 示例应用根组件。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XueHua File Operations',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const FileOperationsHomePage(),
    );
  }
}
