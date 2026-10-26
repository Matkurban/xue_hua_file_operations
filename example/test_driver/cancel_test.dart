import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  late FlutterDriver driver;
  setUpAll(() async { driver = await FlutterDriver.connect(); });
  tearDownAll(() async { await driver.close(); });
  Future<String> status() => driver.getText(find.byValueKey('status'));
  Future<void> waitStatus(bool Function(String) t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      if (t(await status())) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    fail('timeout status=${await status()}');
  }
  test('cancels', () async {
    expect(await status(), 'Ready');
    for (final key in ['pickFile', 'pickFiles', 'pickDirectory', 'saveFile']) {
      await driver.tap(find.byValueKey(key));
      await waitStatus((s) => s == 'Cancelled', const Duration(seconds: 15));
      // ignore: avoid_print
      print('EVIDENCE cancel $key OK');
    }
  });
}
