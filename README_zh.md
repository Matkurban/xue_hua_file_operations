# xue_hua_file_operations

[English](README.md) | 中文

跨平台 Flutter 插件：支持选择文件与目录、另存为（Save As），以及使用系统默认应用打开文件。

**仓库地址：** [https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)

## 功能特性

- 选择单个文件（`pickFile`）或多个文件（`pickFiles`）
- 支持按 `FileType`、扩展名和/或 MIME 类型过滤
- 多选可选 `maxFiles` 上限（在用户选择后校验）
- 选择目录（`pickDirectory`）
- 另存为（`saveFile`）：写入字节，或从源路径复制
- 使用系统默认处理程序打开文件（`openFile`）
- 统一的 `PlatformFile` 模型，以及类型化异常 `FileOperationsException` / `ErrorCode`

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  xue_hua_file_operations: ^1.0.0
```

然后执行：

```bash
flutter pub get
```

## 支持的平台

| 平台 | 是否支持 | 说明 |
|------|----------|------|
| Android | 是 | Storage Access Framework (SAF) / Activity Result API |
| iOS | 是 | `UIDocumentPicker` / 文档交互 |
| macOS | 是 | 原生 `NSOpenPanel` / `NSSavePanel` |
| Windows | 是 | 原生文件 / 文件夹对话框 |
| Linux | 是 | 原生文件 / 文件夹对话框 |
| Web | 是 | HTML `<input type="file">` 与 Blob 下载 |

### `path` 与 `identifier` 行为

| 平台 | `path` | 说明 |
|------|--------|------|
| Android / iOS / 桌面 | 通常非空（缓存副本或文件系统路径） | `identifier` 保留原生 URI / URL / bookmark |
| Web | 始终为 `null` | 始终加载 `bytes`；保存触发下载；打开需要 object URL 形式的 `identifier` |

### 目录选择

| 平台 | 返回内容 | 说明 |
|------|----------|------|
| Android | SAF 树 URI，位于 `path` / `identifier` | 在可能时会申请可持久化读权限 |
| iOS | 展示用 `path` + 安全作用域 **bookmark**（在 `identifier` 中） | 后续访问 / `openFile` 请优先使用 `identifier`；仅路径不可长期使用 |
| macOS / Windows / Linux | 真实文件系统路径 | 原生文件夹对话框 |
| Web | 通过 `webkitdirectory` 得到文件夹名 | 不是真实 FS 路径；能力取决于浏览器 |

## 平台配置与权限

### Android

**权限：** 不需要危险级存储权限（如 `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / 媒体权限）。插件使用系统文档选择器（SAF）。

**FileProvider：** 插件已注册自有 `FileProvider`，用于通过 content URI 打开文件。基础使用无需在宿主 App 中额外配置 FileProvider。

**宿主 Activity（必需）：** 宿主 `Activity` 必须继承 `FlutterFragmentActivity`（不能使用普通的 `FlutterActivity`），因为选择器依赖 Activity Result contracts：

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### iOS

**权限：** 使用本插件的文档选择 / 保存 / 打开 API 时，无需额外在 Info.plist 中配置相册等隐私用途说明键。

**目录访问：** 用户选择目录后，插件会在 `DirectoryResult.identifier` 中保存带前缀的安全作用域 bookmark。后续访问或调用 `openFile` 时请优先使用该 `identifier`；仅依赖展示用 `path` 在应用重启后不可靠。

### macOS

**Entitlements（App Sandbox）：** 若应用启用了 App Sandbox（Mac App Store / 常见 Flutter macOS 应用），需要添加用户选择文件读写权限：

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

可参考示例工程 `example/macos/Runner/` 下的 entitlements。

### Windows

**权限：** 无需额外权限。使用系统原生文件 / 文件夹对话框，无需为本插件添加额外清单配置。

### Linux

**权限：** 无需额外权限。使用系统原生文件 / 文件夹对话框，无需为本插件添加额外桌面权限。

### Web

**权限：** 应用层无需额外权限。浏览器会展示自带的文件选择 / 下载界面。打开选择器通常需要用户手势。

**限制：**

- `path` 始终为 `null`
- 选中的文件始终包含 `bytes`
- `saveFile` 必须提供 `bytes`（不支持 `sourcePath`）
- `openFile` 必须提供 object URL 形式的 `identifier`（例如来自先前选择）；不支持本地文件系统路径

## 快速开始

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;

// 选择单个文件
final file = await ops.pickFile(withData: false);

// 选择多个文件（可选上限）
final files = await ops.pickFiles(maxFiles: 5, type: FileType.image);

// 选择目录
final dir = await ops.pickDirectory();

// 另存为
await ops.saveFile(
  fileName: 'export.txt',
  bytes: file?.bytes,
  sourcePath: file?.path,
);

// 打开
await ops.openFile(path: file?.path, identifier: file?.identifier);
```

用户取消返回 `null`。硬性失败会抛出 `FileOperationsException`。

## API 参考

通过单例访问 API：

```dart
XueHuaFileOperations.instance
```

### `pickFile`

选择单个文件。用户取消时返回 `null`。

```dart
Future<PlatformFile?> pickFile({
  bool withData = false,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  List<String>? allowedMimeTypes,
})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `withData` | `bool` | `false` | 为 `true` 时将文件内容读入 `PlatformFile.bytes`。在 Web 上无论该标志如何都会加载 bytes。 |
| `dialogTitle` | `String?` | `null` | 原生对话框标题（在支持的平台上，如桌面）。部分平台可能忽略（如 Android SAF、Web）。 |
| `type` | `FileType` | `FileType.any` | 高级类型过滤：`any`、`image`、`video`、`audio` 或 `custom`。 |
| `allowedExtensions` | `List<String>?` | `null` | 允许的扩展名（可带或不带前导 `.`），例如 `['pdf', 'txt']`。常与 `FileType.custom` 配合，或作为附加过滤。 |
| `allowedMimeTypes` | `List<String>?` | `null` | 允许的 MIME 类型，例如 `['application/pdf']`。具体行为取决于平台选择器。 |

**返回值：** `PlatformFile?` — 选中的文件；取消时为 `null`。

### `pickFiles`

选择多个文件。用户取消时返回 `null`。

```dart
Future<List<PlatformFile>?> pickFiles({
  int? maxFiles,
  bool withData = false,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  List<String>? allowedMimeTypes,
})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `maxFiles` | `int?` | `null` | 允许选择的最大文件数。`null` 表示不限制。若提供则必须 `>= 1`。若用户选择数量超过 `maxFiles`，抛出带 `ErrorCode.tooManyFiles` 的 `FileOperationsException`。 |
| `withData` | `bool` | `false` | 同 `pickFile`。 |
| `dialogTitle` | `String?` | `null` | 同 `pickFile`。 |
| `type` | `FileType` | `FileType.any` | 同 `pickFile`。 |
| `allowedExtensions` | `List<String>?` | `null` | 同 `pickFile`。 |
| `allowedMimeTypes` | `List<String>?` | `null` | 同 `pickFile`。 |

**返回值：** `List<PlatformFile>?` — 选中的文件列表；取消时为 `null`。

**异常：** 若提供了 `maxFiles` 且 `< 1`，抛出 `ErrorCode.invalidArgs`。

### `pickDirectory`

选择目录。用户取消时返回 `null`。

```dart
Future<DirectoryResult?> pickDirectory({String? dialogTitle})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `dialogTitle` | `String?` | `null` | 原生文件夹对话框标题（在支持的平台上）。 |

**返回值：** `DirectoryResult?` — 目录信息；取消时为 `null`。

各平台 `path` / `identifier` 含义见 [目录选择](#目录选择)。

### `saveFile`

显示另存为对话框，将 `bytes` 写入目标，或从 `sourcePath` 复制。

```dart
Future<SaveFileResult?> saveFile({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  List<String>? allowedExtensions,
  String? dialogTitle,
})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `fileName` | `String` | *（必填）* | 保存对话框中的建议文件名；Web 上为下载文件名。 |
| `bytes` | `Uint8List?` | `null` | 要写入的文件内容。Web 上必填。其他平台需提供 `bytes` 和/或 `sourcePath`。 |
| `sourcePath` | `String?` | `null` | 要复制到所选目标的现有文件路径。Web 不支持。 |
| `allowedExtensions` | `List<String>?` | `null` | 可选的扩展名过滤 / 提示（在支持的平台上）。 |
| `dialogTitle` | `String?` | `null` | 原生保存对话框标题（在支持的平台上）。 |

**返回值：** `SaveFileResult?` — 保存结果；取消时为 `null`。

**异常：**

- 若 `bytes` 与 `sourcePath` 均缺失 / 为空，抛出 `ErrorCode.invalidArgs`
- 在 Web 上若 `bytes` 为 null（例如只提供了 `sourcePath`），抛出 `ErrorCode.unsupported`

### `openFile`

使用系统默认应用打开文件。

```dart
Future<void> openFile({String? path, String? identifier})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `path` | `String?` | `null` | 要打开的文件系统路径（或平台可访问路径）。 |
| `identifier` | `String?` | `null` | 原生标识：Android content URI、iOS bookmark/URL、Web object URL 等。 |

`path` 与 `identifier` 至少提供一个非空值。

**异常：**

- 两者都缺失 / 为空时抛出 `ErrorCode.invalidArgs`
- 在 Web 上仅提供本地 `path` 时抛出 `ErrorCode.unsupported`（应传入 object URL 形式的 `identifier`）

## 数据模型

### `PlatformFile`

表示由插件选择或产生的文件。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 文件名（如 `report.pdf`） |
| `size` | `int` | 大小（字节） |
| `path` | `String?` | 可用时为本地路径；Web 上为 `null` |
| `bytes` | `Uint8List?` | 在 `withData: true` 或 Web 上为文件内容 |
| `identifier` | `String?` | 原生唯一标识（URI、bookmark、object URL 等） |
| `hasBytes` | `bool` | 便捷属性：`bytes != null` |

### `DirectoryResult`

`pickDirectory` 的返回结果。

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | 展示 / 文件系统路径，或树 URI / 文件夹名（视平台而定） |
| `name` | `String` | 目录显示名称 |
| `identifier` | `String?` | 可用时的持久原生标识（如 iOS bookmark、Android 树 URI） |

### `SaveFileResult`

`saveFile` 的返回结果。

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 已保存文件名（Web 上为下载名） |
| `path` | `String?` | 移动端 / 桌面端为绝对路径；Web 上为 `null` |

### `FileType`

选择对话框的高级类型过滤：

| 值 | 含义 |
|----|------|
| `FileType.any` | 不限制类型 |
| `FileType.image` | 图片 |
| `FileType.video` | 视频 |
| `FileType.audio` | 音频 |
| `FileType.custom` | 依赖 `allowedExtensions` / `allowedMimeTypes` |

## 错误处理

硬性失败会抛出 `FileOperationsException`：

| 属性 | 类型 | 说明 |
|------|------|------|
| `code` | `ErrorCode` | 机器可读错误码 |
| `message` | `String` | 可读错误信息 |
| `details` | `Object?` | 可选附加上下文 |

### `ErrorCode`

| 枚举值 | 线传值 | 典型含义 |
|--------|--------|----------|
| `cancelled` | `cancelled` | 预留取消码（用户取消通常返回 `null`） |
| `permissionDenied` | `permission_denied` | 权限 / 访问被拒绝 |
| `invalidArgs` | `invalid_args` | 方法参数无效 |
| `tooManyFiles` | `too_many_files` | 选择数量超过 `maxFiles` |
| `notFound` | `not_found` | 文件或资源未找到 |
| `ioError` | `io_error` | 读写过程中的 I/O 失败 |
| `unsupported` | `unsupported` | 当前平台 / 配置不支持该操作 |
| `unknown` | `unknown` | 未预期 / 未分类错误 |

## 相关链接

- GitHub：[https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)
- 更新日志：[CHANGELOG.md](CHANGELOG.md)
- 许可证：[LICENSE](LICENSE)
