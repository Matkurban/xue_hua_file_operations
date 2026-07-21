import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_file_operations_example/main.dart';

void main() {
  testWidgets('Demo page loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('XueHua File Operations'), findsOneWidget);
    expect(find.text('Pick File'), findsOneWidget);
    expect(find.text('Pick Files'), findsOneWidget);
  });
}
