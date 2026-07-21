## 1.0.0

* Initial stable release.
* Singleton API via `XueHuaFileOperations.instance`.
* File operations: `pickFile`, `pickFiles`, `pickDirectory`, `saveFile`, `openFile`.
* Models: `PlatformFile`, `DirectoryResult`, `SaveFileResult`, `FileType`.
* Typed errors: `FileOperationsException` with unified `ErrorCode` values.
* Supported platforms: Android, iOS, macOS, Windows, Linux, and Web.
