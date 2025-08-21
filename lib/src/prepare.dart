import "dart:io";
import "dart:convert";

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:desktop_updater/src/file_hash.dart";
import "package:http/http.dart" as http;
import "package:path/path.dart" as path;

Future<List<FileHashModel?>> prepareUpdateAppFunction({
  required String remoteUpdateFolder,
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

    final newHashFileUrl = "$remoteUpdateFolder/hashes.json";
    final newHashFileRequest = http.Request("GET", Uri.parse(newHashFileUrl));
    final newHashFileResponse = await client.send(newHashFileRequest);

    // temp dizinindeki dosyaları kopyala
    // dir + output.txt dosyası oluşturulur
    final outputFile =
        File("${tempDir.path}${Platform.pathSeparator}hashes.json");

    // Çıktı dosyasını açıyoruz
    final sink = outputFile.openWrite();

    // Save the file
    await newHashFileResponse.stream.pipe(sink);

    // Close the file
    await sink.close();

    // Compute changes directly from remote hashes
    final remoteHashesStr = await outputFile.readAsString();
    final remoteHashes = (jsonDecode(remoteHashesStr) as List<dynamic>)
        .map<FileHashModel?>((e) => FileHashModel.fromJson(e))
        .whereType<FileHashModel>()
        .toList();

    final changes = <FileHashModel>[];

    for (final remote in remoteHashes) {
      final parts = remote.filePath.split(RegExp(r"[\\/]+"));
      final localFullPath = path.joinAll([dir.path, ...parts]);
      final localFile = File(localFullPath);

      if (!await localFile.exists()) {
        changes.add(remote);
        continue;
      }

      final localHash = await getFileHash(localFile);
      if (localHash.isEmpty || localHash != remote.calculatedHash) {
        changes.add(remote);
      }
    }

    return changes;
  }
  return [];
}
