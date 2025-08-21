import "dart:convert";
import "dart:io";

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/file_hash.dart";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:path/path.dart" as path;

String _normalizePlatform(String s) {
  final v = s.toLowerCase();
  if (v == "win" || v == "win32" || v == "windows") return "windows";
  if (v == "mac" || v == "macos" || v == "darwin" || v == "osx") {
    return "macos";
  }
  if (v == "linux" || v == "gnu/linux") return "linux";
  return v;
}

Future<ItemModel?> versionCheckFunction({
  required String appArchiveUrl,
}) async {
  debugPrint("[DesktopUpdater] versionCheck start url=$appArchiveUrl");
  final executablePath = Platform.resolvedExecutable;
  debugPrint("[DesktopUpdater] resolvedExecutable=$executablePath");

  final directoryPath = executablePath.substring(
    0,
    executablePath.lastIndexOf(Platform.pathSeparator),
  );

  var dir = Directory(directoryPath);

  if (Platform.isMacOS) {
    dir = dir.parent;
  }
  debugPrint("[DesktopUpdater] app dir used=${dir.path}");

  // Eğer belirtilen yol bir dizinse
  if (await dir.exists()) {
    // temp dizini oluşturulur
    final tempDir = await Directory.systemTemp.createTemp("desktop_updater");

    // Download oldHashFilePath
    final client = http.Client();

    final appArchive = http.Request("GET", Uri.parse(appArchiveUrl));
    final appArchiveResponse = await client.send(appArchive);

    // temp dizinindeki dosyaları kopyala
    // dir + output.txt dosyası oluşturulur
    final outputFile =
        File("${tempDir.path}${Platform.pathSeparator}app-archive.json");

    // Çıktı dosyasını açıyoruz
    final sink = outputFile.openWrite();

    // Save the file
    await appArchiveResponse.stream.pipe(sink);

    // Close the file and the http client
    await sink.close();
    client.close();
    debugPrint(
        "[DesktopUpdater] downloaded app-archive.json -> ${outputFile.path} bytes=${await outputFile.length()}");

    if (!outputFile.existsSync()) {
      throw Exception("Desktop Updater: App archive do not exist");
    }

    final appArchiveString = await outputFile.readAsString();

    // Decode as List<FileHashModel?>
    final appArchiveDecoded = AppArchiveModel.fromJson(
      jsonDecode(appArchiveString),
    );

    final targetPlatform = _normalizePlatform(Platform.operatingSystem);
    final versions = appArchiveDecoded.items
        .where(
          (element) => _normalizePlatform(element.platform) == targetPlatform,
        )
        .toList();
    debugPrint(
        "[DesktopUpdater] items=${appArchiveDecoded.items.length} targetPlatform=$targetPlatform filtered=${versions.length}");

    if (versions.isEmpty) {
      throw Exception("Desktop Updater: No version found for this platform");
    }

    // Get the latest version with shortVersion number
    final latestVersion = versions.reduce(
      (value, element) {
        if (value.shortVersion > element.shortVersion) {
          return value;
        }
        return element;
      },
    );
    debugPrint(
        "[DesktopUpdater] latest version=${latestVersion.version} short=${latestVersion.shortVersion} url=${latestVersion.url}");

    String? currentVersion;
    if (Platform.isLinux) {
      final exePath = await File("/proc/self/exe").resolveSymbolicLinks();
      final appPath = path.dirname(exePath);
      final assetPath = path.join(appPath, "data", "flutter_assets");
      final versionPath = path.join(assetPath, "version.json");
      final versionJson = jsonDecode(await File(versionPath).readAsString());
      currentVersion = versionJson["build_number"]?.toString();
    } else {
      try {
        currentVersion = await DesktopUpdater().getCurrentVersion();
      } catch (_) {
        currentVersion = null;
      }

      // Fallback for Windows/macOS: read from assets if available
      if (currentVersion == null || currentVersion.isEmpty) {
        final exePath = Platform.resolvedExecutable;
        final appPath = path.dirname(exePath);
        final assetPath = path.join(appPath, "data", "flutter_assets");
        final versionPath = path.join(assetPath, "version.json");
        final versionFile = File(versionPath);
        if (await versionFile.exists()) {
          final versionJson = jsonDecode(await versionFile.readAsString());
          currentVersion = versionJson["build_number"]?.toString();
        }
      }
    }
    debugPrint("[DesktopUpdater] currentVersion(raw)=$currentVersion");

    if (currentVersion == null) {
      throw Exception("Desktop Updater: Current version is null");
    }

    // Robustly parse build number (handle strings like "9", "9-windows", etc.)
    int? currentBuild = int.tryParse(currentVersion.trim());
    if (currentBuild == null) {
      final m = RegExp(r"(\d+)").firstMatch(currentVersion);
      if (m != null) {
        currentBuild = int.tryParse(m.group(1)!);
      }
    }
    debugPrint(
        "[DesktopUpdater] parsed currentBuild=$currentBuild vs latestShort=${latestVersion.shortVersion}");

    if (currentBuild == null) {
      throw Exception(
          "Desktop Updater: Unable to parse current build number: $currentVersion");
    }

    if (latestVersion.shortVersion > currentBuild) {
      // calculate totalSize
      final tempDir = await Directory.systemTemp.createTemp("desktop_updater");

      final client = http.Client();

      // Build a robust URL for hashes.json and handle '+' encoding edge-cases
      final baseUri = Uri.parse(latestVersion.url);
      Uri newHashUri = baseUri.replace(
        path: baseUri.path.endsWith("/")
            ? "${baseUri.path}hashes.json"
            : "${baseUri.path}/hashes.json",
      );
      debugPrint("[DesktopUpdater] request hashes.json -> $newHashUri");
      http.StreamedResponse newHashFileResponse =
          await client.send(http.Request("GET", newHashUri));
      debugPrint(
          "[DesktopUpdater] hashes.json status=${newHashFileResponse.statusCode}");

      // Retry with %2B-encoded '+' if the first attempt fails
      if (newHashFileResponse.statusCode != 200) {
        final encodedUrl = newHashUri.toString().replaceAll("+", "%2B");
        debugPrint(
            "[DesktopUpdater] retry hashes.json with %2B -> $encodedUrl");
        newHashFileResponse =
            await client.send(http.Request("GET", Uri.parse(encodedUrl)));
        debugPrint(
            "[DesktopUpdater] hashes.json retry status=${newHashFileResponse.statusCode}");
      }

      if (newHashFileResponse.statusCode != 200) {
        client.close();
        throw const HttpException("Failed to download hashes.json");
      }

      final outputFile =
          File("${tempDir.path}${Platform.pathSeparator}hashes.json");
      final sink = outputFile.openWrite();

      await newHashFileResponse.stream.listen(
        sink.add,
        onDone: () async {
          await sink.close();
          client.close();
        },
        onError: (e) async {
          await sink.close();
          client.close();
          throw e;
        },
        cancelOnError: true,
      ).asFuture();

      final oldHashFilePath = await genFileHashes();
      final newHashFilePath = outputFile.path;
      debugPrint(
          "[DesktopUpdater] oldHashFilePath=$oldHashFilePath newHashFilePath=$newHashFilePath");

      final changedFiles = await verifyFileHashes(
        oldHashFilePath,
        newHashFilePath,
      );
      debugPrint("[DesktopUpdater] changedFiles count=${changedFiles.length}");

      return latestVersion.copyWith(
        changedFiles: changedFiles,
        appName: appArchiveDecoded.appName,
      );
    } else {
      debugPrint(
          "[DesktopUpdater] No update available (current=$currentBuild, latest=${latestVersion.shortVersion})");
    }
  }
  return null;
}
