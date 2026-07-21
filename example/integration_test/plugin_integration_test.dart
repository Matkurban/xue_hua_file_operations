import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('singleton is available', (WidgetTester tester) async {
    expect(XueHuaFileOperations.instance, isNotNull);
  });
}
