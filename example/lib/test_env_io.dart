import 'dart:io';

/// True when flutter_driver / automation hooks are present in the process env.
bool get hasAutomatedTestEnv => const [
      'XUE_HUA_CAMERA_TEST_AUTO',
      'XUE_HUA_TEST_PICK_FILE',
      'XUE_HUA_TEST_PICK_FILES',
      'XUE_HUA_TEST_PICK_DIR',
      'XUE_HUA_TEST_SAVE_FILE',
      'XUE_HUA_TEST_OPEN_FILE',
      'XUE_HUA_EXPECT',
    ].any(Platform.environment.containsKey);
