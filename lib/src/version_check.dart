import "dart:convert";
import "dart:io";

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/file_hash.dart";
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
  final executablePath = Platform.resolvedExecutable;

  final directoryPath = executablePath.substring(
    0,
    executablePath.lastIndexOf(Platform.pathSeparator),
  );

  var dir = Directory(directoryPath);

  if (Platform.isMacOS) {
    dir = dir.parent;
  }

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

  late String? currentVersion;

    if (Platform.isLinux) {
      final exePath = await File("/proc/self/exe").resolveSymbolicLinks();
      final appPath = path.dirname(exePath);
      final assetPath = path.join(appPath, "data", "flutter_assets");
      final versionPath = path.join(assetPath, "version.json");
      final versionJson = jsonDecode(await File(versionPath).readAsString());

      currentVersion = versionJson["build_number"];
    } else {
      await DesktopUpdater().getCurrentVersion().then(
        (value) {
          currentVersion = value;
        },
      );
    }

    if (currentVersion == null) {
      throw Exception("Desktop Updater: Current version is null");
    }

    // Robustly parse build number (handle strings like "9", "9-windows", etc.)
    int? currentBuild = int.tryParse(currentVersion!.trim());
    if (currentBuild == null) {
      final m = RegExp(r"(\d+)").firstMatch(currentVersion!);
      if (m != null) {
        currentBuild = int.tryParse(m.group(1)!);
      }
    }

    if (currentBuild == null) {
      throw Exception("Desktop Updater: Unable to parse current build number: $currentVersion");
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

      http.StreamedResponse newHashFileResponse =
          await client.send(http.Request("GET", newHashUri));

      // Retry with %2B-encoded '+' if the first attempt fails
      if (newHashFileResponse.statusCode != 200) {
        final encodedUrl = newHashUri.toString().replaceAll("+", "%2B");
        newHashFileResponse =
            await client.send(http.Request("GET", Uri.parse(encodedUrl)));
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

      final changedFiles = await verifyFileHashes(
        oldHashFilePath,
        newHashFilePath,
      );

      if (changedFiles.isEmpty) {}

      return latestVersion.copyWith(
        changedFiles: changedFiles,
        appName: appArchiveDecoded.appName,
      );
    } else {}
  }
  return null;
}
