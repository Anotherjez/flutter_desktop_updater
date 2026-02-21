import "dart:math" as math;
import "dart:io";

import "package:desktop_updater/desktop_updater.dart";
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

  final _plugin = DesktopUpdater();

  void init(Uri url) {
    _appArchiveUrl = url;
    checkVersion();
    notifyListeners();
  }

  void makeSkipUpdate() {
    _skipUpdate = true;
    notifyListeners();
  }

  Future<void> checkVersion() async {
    if (_appArchiveUrl == null) {
      throw Exception("App archive URL is not set");
    }

    final versionResponse = await _plugin.versionCheck(
      appArchiveUrl: appArchiveUrl.toString(),
    );

    if (versionResponse?.url != null) {
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
          notifyListeners();
        }).catchError((_) {
          // ignore background errors; will retry on explicit download
          _isPreparing = false;
          notifyListeners();
        });
      }

      notifyListeners();
    }
  }

  Future<void> downloadUpdate() async {
    if (_folderUrl == null) {
      throw Exception("Folder URL is not set");
    }

    // Guard against re-entrancy (double taps)
    if (_isDownloading) return;
    _isDownloading = true;
    _isDownloaded = false;
    _isPreparing = _changedFiles == null || _changedFiles!.isEmpty;
    notifyListeners();

    // Lazily prepare changed files if not already present
    if (_changedFiles == null || _changedFiles!.isEmpty) {
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
      notifyListeners();
    }

    try {
      final stream = await _plugin.updateApp(
        remoteUpdateFolder: _folderUrl!,
        changedFiles: _changedFiles ?? [],
      );

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
        notifyListeners();
      }

      final filesAreReady = await _verifyDownloadedFiles();

      _isDownloading = false;
      _isPreparing = false;
      if (filesAreReady) {
        _downloadProgress = 1.0;
        _downloadedSize = _downloadSize;
        _isDownloaded = true;
      } else {
        _isDownloaded = false;
      }
      notifyListeners();
    } catch (_) {
      _isDownloading = false;
      _isPreparing = false;
      _isDownloaded = false;
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
        return false;
      }

      final expectedLength = item.length;
      if (expectedLength > 0) {
        final actualLength = await localFile.length();
        if (actualLength != expectedLength) {
          return false;
        }
      }
    }

    return true;
  }

  void restartApp() {
    _plugin.restartApp();
  }
}
