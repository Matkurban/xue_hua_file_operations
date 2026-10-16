import 'package:flutter_driver/driver_extension.dart';
import 'package:xue_hua_file_operations_example/main.dart' as app;

/// App entry used by `flutter drive`: enables the Flutter Driver extension,
/// then starts the example app.
void main() {
  enableFlutterDriverExtension();
  app.main();
}
