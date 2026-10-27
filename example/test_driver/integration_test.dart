// Prefer `flutter test integration_test -d DEVICE` from example/.
// `flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/plugin_integration_test.dart -d DEVICE`
// also works (integration_test successor to flutter_driver).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
