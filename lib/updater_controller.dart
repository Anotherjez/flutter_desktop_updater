import "dart:async";
import "dart:io";
import "dart:math" as math;

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/file_hash.dart";
import "package:flutter/material.dart";

class DesktopUpdaterController extends ChangeNotifier {
  DesktopUpdaterController({
    required Uri? appArchiveUrl,
    this.localization,
  }) {
    if (appArchiveUrl != null) {
      init(appArchiveUrl);
    }
  }

  DesktopUpdateLocalization? localization;
  DesktopUpdateLocalization? get getLocalization => localization;

  String? _appName;
  String? get appName => _appName;

  String? _appVersion;
  String? get appVersion => _appVersion;

  Uri? _appArchiveUrl;
  Uri? get appArchiveUrl => _appArchiveUrl;

  bool _needUpdate = false;
  bool get needUpdate => _needUpdate;

  bool _isMandatory = false;
  bool get isMandatory => _isMandatory;

  String? _folderUrl;

  UpdateProgress? _updateProgress;
  UpdateProgress? get updateProgress => _updateProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isPreparing = false;
  bool get isPreparing => _isPreparing;

  bool _isDownloaded = false;
  bool get isDownloaded => _isDownloaded;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  double _downloadSize = 0;
  double? get downloadSize => _downloadSize;

  double _downloadedSize = 0;
  double get downloadedSize => _downloadedSize;

  List<FileHashModel?>? _changedFiles;

  List<ChangeModel?>? _releaseNotes;
  List<ChangeModel?>? get releaseNotes => _releaseNotes;

  bool _skipUpdate = false;
  bool get skipUpdate => _skipUpdate;

  bool _isCheckingVersion = false;

  final _plugin = DesktopUpdater();

  void init(Uri url) {
    _appArchiveUrl = url;
    unawaited(_log("init: archiveUrl=$url"));
    checkVersion();
    notifyListeners();
  }

  void makeSkipUpdate() {
    _skipUpdate = true;
    notifyListeners();
  }

  Future<void> checkVersion() async {
    if (_isCheckingVersion) {
      unawaited(_log("checkVersion: skipped (already running)"));
      return;
    }

    _isCheckingVersion = true;

    if (_appArchiveUrl == null) {
      _isCheckingVersion = false;
      throw Exception("App archive URL is not set");
    }

    try {
      final versionResponse = await _plugin.versionCheck(
        appArchiveUrl: appArchiveUrl.toString(),
      );

      if (versionResponse?.url != null) {
        unawaited(
          _log(
            "checkVersion: update found version=${versionResponse?.version} short=${versionResponse?.shortVersion} url=${versionResponse?.url}",
          ),
        );
        _needUpdate = true;
        _folderUrl = versionResponse?.url;
        _isMandatory = versionResponse?.mandatory ?? false;

        // Calculate total length in KB (from server-provided lengths)
        _downloadSize = (versionResponse?.changedFiles?.fold<double>(
              0,
              (previousValue, element) =>
                  previousValue + ((element?.length ?? 0) / 1024.0),
            )) ??
            0.0;

        // Get changed files liste
        _changedFiles = versionResponse?.changedFiles;
        _releaseNotes = versionResponse?.changes;
        _appName = versionResponse?.appName;
        _appVersion = versionResponse?.version;

        // Pre-fetch changed files in background to reduce start lag
        if (_folderUrl != null) {
          // Don't await; prepare in background
          _isPreparing = true;
          notifyListeners();
          unawaited(
            _log("checkVersion: preparing changed files in background"),
          );
          DesktopUpdater()
              .prepareUpdateApp(remoteUpdateFolder: _folderUrl!)
              .then((files) {
            _changedFiles = files;
            _downloadSize = (_changedFiles?.fold<double>(
                  0,
                  (prev, e) => prev + ((e?.length ?? 0) / 1024.0),
                )) ??
                0.0;
            _isPreparing = false;

            if ((_changedFiles?.isEmpty ?? true)) {
              _needUpdate = false;
              unawaited(
                _log(
                  "checkVersion: prepare returned 0 changed files, hiding update prompt",
                ),
              );
            }

            unawaited(
              _log(
                "checkVersion: prepare completed changedFiles=${_changedFiles?.length ?? 0} downloadSizeKB=${_downloadSize.toStringAsFixed(2)}",
              ),
            );
            notifyListeners();
          }).catchError((error, stackTrace) {
            // ignore background errors; will retry on explicit download
            _isPreparing = false;
            unawaited(
              _log(
                "checkVersion: prepare failed in background error=$error\n$stackTrace",
              ),
            );
            notifyListeners();
          });
        }

        notifyListeners();
      }
    } finally {
      _isCheckingVersion = false;
    }
  }

  Future<void> downloadUpdate() async {
    if (_folderUrl == null) {
      throw Exception("Folder URL is not set");
    }

    unawaited(_log("downloadUpdate: requested folderUrl=$_folderUrl"));

    // Guard against re-entrancy (double taps)
    if (_isDownloading) return;
    _isDownloading = true;
    _isDownloaded = false;
    _isPreparing = _changedFiles == null || _changedFiles!.isEmpty;
    notifyListeners();

    // Lazily prepare changed files if not already present
    if (_changedFiles == null || _changedFiles!.isEmpty) {
      unawaited(_log("downloadUpdate: changedFiles empty; preparing now"));
      _changedFiles = await _plugin.prepareUpdateApp(
        remoteUpdateFolder: _folderUrl!,
      );

      // Recalculate total size in KB
      _downloadSize = (_changedFiles?.fold<double>(
            0,
            (prev, e) => prev + ((e?.length ?? 0) / 1024.0),
          )) ??
          0.0;
      _isPreparing = false;
      unawaited(
        _log(
          "downloadUpdate: prepare completed changedFiles=${_changedFiles?.length ?? 0} downloadSizeKB=${_downloadSize.toStringAsFixed(2)}",
        ),
      );

      if (_changedFiles == null || _changedFiles!.isEmpty) {
        _isDownloading = false;
        _isDownloaded = false;
        _needUpdate = false;
        unawaited(
          _log(
            "downloadUpdate: no effective changed files after prepare; hiding update prompt",
          ),
        );
        notifyListeners();
        return;
      }

      notifyListeners();
    }

    try {
      final stream = await _plugin.updateApp(
        remoteUpdateFolder: _folderUrl!,
        changedFiles: _changedFiles ?? [],
      );

      unawaited(
        _log(
          "downloadUpdate: stream started changedFiles=${_changedFiles?.length ?? 0}",
        ),
      );

      var lastLoggedPercent = -1;

      await for (final event in stream) {
        _updateProgress = event;

        _isDownloading = true;
        _isDownloaded = false;

        final totalBytes = event.totalBytes;
        final bytesProgress = totalBytes <= 0
            ? 0.0
            : math.min(1.0, math.max(0.0, event.receivedBytes / totalBytes));

        final filesProgress = event.totalFiles <= 0
            ? 0.0
            : math.min(
                1.0,
                math.max(0.0, event.completedFiles / event.totalFiles),
              );

        _downloadProgress = math.max(bytesProgress, filesProgress);
        _downloadedSize = _downloadSize * _downloadProgress;

        final progressPercent = (_downloadProgress * 100).floor();
        if (progressPercent >= 0 && progressPercent % 10 == 0) {
          if (progressPercent != lastLoggedPercent) {
            lastLoggedPercent = progressPercent;
            unawaited(
              _log(
                "downloadUpdate: progress=${progressPercent}% files=${event.completedFiles}/${event.totalFiles} bytes=${event.receivedBytes.toStringAsFixed(2)}/${event.totalBytes.toStringAsFixed(2)} currentFile=${event.currentFile}",
              ),
            );
          }
        }

        notifyListeners();
      }

      final filesAreReady = await _verifyDownloadedFiles();

      _isDownloading = false;
      _isPreparing = false;
      if (filesAreReady) {
        _downloadProgress = 1.0;
        _downloadedSize = _downloadSize;
        _isDownloaded = true;
        unawaited(_log("downloadUpdate: verification passed, restart enabled"));
      } else {
        _isDownloaded = false;
        unawaited(
          _log("downloadUpdate: verification failed, restart not enabled"),
        );
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _isDownloading = false;
      _isPreparing = false;
      _isDownloaded = false;
      unawaited(_log("downloadUpdate: failed error=$error\n$stackTrace"));
      notifyListeners();
    }
  }

  Future<bool> _verifyDownloadedFiles() async {
    final changedFiles = _changedFiles;
    if (changedFiles == null || changedFiles.isEmpty) {
      return false;
    }

    final executablePath = Platform.resolvedExecutable;
    final directoryPath = executablePath.substring(
      0,
      executablePath.lastIndexOf(Platform.pathSeparator),
    );

    var dir = Directory(directoryPath);
    if (Platform.isMacOS) {
      dir = dir.parent;
    }

    final updateDir = Directory("${dir.path}${Platform.pathSeparator}update");
    if (!await updateDir.exists()) {
      await _log("verify: update folder missing path=${updateDir.path}");
      return false;
    }

    for (final item in changedFiles) {
      if (item == null) continue;

      final normalizedPath = item.filePath
          .replaceAll("/", Platform.pathSeparator)
          .replaceAll("\\", Platform.pathSeparator);
      final localFile =
          File("${updateDir.path}${Platform.pathSeparator}$normalizedPath");

      if (!await localFile.exists()) {
        await _log("verify: missing file path=${localFile.path}");
        return false;
      }

      final expectedLength = item.length;
      if (expectedLength > 0) {
        final actualLength = await localFile.length();
        if (actualLength <= 0) {
          await _log("verify: zero size path=${localFile.path}");
          return false;
        }
      }

      final expectedHash = item.calculatedHash;
      if (expectedHash.isNotEmpty) {
        final actualHash = await getFileHash(localFile);
        if (actualHash.isEmpty) {
          await _log("verify: empty hash path=${localFile.path}");
          return false;
        }

        if (actualHash != expectedHash) {
          final lowerPath = normalizedPath.toLowerCase();
          final isCriticalBinary = lowerPath.endsWith(".exe") ||
              lowerPath.endsWith(".dll") ||
              lowerPath.endsWith(".so") ||
              lowerPath.endsWith(".dylib");

          if (isCriticalBinary) {
            await _log(
              "verify: hash mismatch (critical) path=${localFile.path} expected=$expectedHash actual=$actualHash",
            );
            return false;
          }

          await _log(
            "verify: hash mismatch (non-critical, continuing) path=${localFile.path} expected=$expectedHash actual=$actualHash",
          );
        }
      }
    }

    await _log(
        "verify: all files validated changedFiles=${changedFiles.length}");
    return true;
  }

  void restartApp() {
    unawaited(_log("restartApp: method invoked"));
    _plugin.restartApp();
  }

  Future<void> _log(String message) async {
    try {
      final logPath =
          "${Directory.systemTemp.path}${Platform.pathSeparator}desktop_updater.log";
      final now = DateTime.now().toIso8601String();
      final logFile = File(logPath);
      await logFile.writeAsString(
        "[$now] $message${Platform.lineTerminator}",
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
}
