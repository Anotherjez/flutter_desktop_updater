import "dart:async";
import "dart:convert";
import "dart:io";

import "package:cryptography_plus/cryptography_plus.dart";
import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:path/path.dart" as p;

Future<String> getFileHash(File file) async {
  try {
    // Stream the file to avoid loading into memory
    final algo = Blake2b();
    final sink = algo.newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return base64.encode(hash.bytes);
  } catch (e) {
    return "";
  }
}

Future<List<FileHashModel?>> verifyFileHashes(
  String oldHashFilePath,
  String newHashFilePath,
) async {
  if (oldHashFilePath == newHashFilePath) {
    return [];
  }

  final oldFile = File(oldHashFilePath);
  final newFile = File(newHashFilePath);

  if (!oldFile.existsSync() || !newFile.existsSync()) {
    throw Exception("Desktop Updater: Hash files do not exist");
  }

  final oldString = await oldFile.readAsString();
  final newString = await newFile.readAsString();

  // Decode as List<FileHashModel?>
  final oldHashes = (jsonDecode(oldString) as List<dynamic>)
      .map<FileHashModel?>(
        (e) => FileHashModel.fromJson(e as Map<String, dynamic>),
      )
      .toList();
  final newHashes = (jsonDecode(newString) as List<dynamic>)
      .map<FileHashModel?>(
        (e) => FileHashModel.fromJson(e as Map<String, dynamic>),
      )
      .toList();

  final changes = <FileHashModel?>[];

  for (final newHash in newHashes) {
    final oldHash = oldHashes.firstWhere(
      (element) => element?.filePath == newHash?.filePath,
      orElse: () => null,
    );

    if (oldHash == null || oldHash.calculatedHash != newHash?.calculatedHash) {
      changes.add(
        FileHashModel(
          filePath: newHash?.filePath ?? "",
          calculatedHash: newHash?.calculatedHash ?? "",
          length: newHash?.length ?? 0,
        ),
      );
    }
  }

  return changes;
}

// Dizin içindeki tüm dosyaların hash'lerini alıp bir dosyaya yazan fonksiyon
Future<String> genFileHashes({String? path}) async {
  path ??= Platform.resolvedExecutable;

  final directoryPath =
      path.substring(0, path.lastIndexOf(Platform.pathSeparator));

  var dir = Directory(directoryPath);

  if (Platform.isMacOS) {
    dir = dir.parent;
  }

  // Eğer belirtilen yol bir dizinse
  if (await dir.exists()) {
    // temp dizini oluşturulur
    final tempDir = await Directory.systemTemp.createTemp("desktop_updater");

    // temp dizinindeki dosyaları kopyala
    // dir + output.txt dosyası oluşturulur
    final outputFile =
        File("${tempDir.path}${Platform.pathSeparator}hashes.json");

    // Çıktı dosyasını açıyoruz (streaming JSON)
    final sink = outputFile.openWrite();

    // JSON array start
    sink.write("[");
    var first = true;

    // Dizin içindeki tüm dosyaları döngüyle okuyoruz
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final relativePath = entity.path.substring(dir.path.length + 1);
      final parts = p.split(relativePath);

      // Exclude updater artifacts and temp files
      final isHashesJson = p.equals(relativePath, "hashes.json");
      final isDSStore = relativePath.endsWith(".DS_Store");
      final isInUpdateDir = parts.isNotEmpty && parts.first.toLowerCase() == "update";
      if (isHashesJson || isDSStore || isInUpdateDir) {
        continue;
      }

      final hash = await getFileHash(entity);
      if (hash.isEmpty) continue;

      final obj = FileHashModel(
        filePath: relativePath,
        calculatedHash: hash,
        length: entity.lengthSync(),
      ).toJson();

      if (!first) {
        sink.write(",");
      } else {
        first = false;
      }
      sink.write(jsonEncode(obj));
    }

    // JSON array end
    sink.write("]");

    // Çıktıyı kaydediyoruz
    await sink.close();
    return outputFile.path;
  } else {
    throw Exception("Desktop Updater: Directory does not exist");
  }
}
