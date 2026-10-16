#include <flutter_linux/flutter_linux.h>

#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin.h"

// Placeholder for unit-testable helpers.
gboolean xue_hua_file_operations_plugin_is_supported(void);

// Error response returned for capturePhoto / captureVideo on Linux.
FlMethodResponse* xue_hua_file_operations_plugin_capture_unsupported(void);
