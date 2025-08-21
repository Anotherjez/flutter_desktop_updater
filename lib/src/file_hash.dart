import "dart:async";
import "dart:convert";
import "dart:io";

import "package:cryptography_plus/cryptography_plus.dart";
import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:path/path.dart" as p;

Future<String> getFileHash(File file) async {
  try {
    // Stream the file into the hash sink to avoid loading the whole file in memory
    final algorithm = Blake2b();
    final sink = algorithm.newHashSink();

    // Read file in chunks and feed to the sink
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }

    sink.close();
    final hash = await sink.hash();

    // Return base64-encoded hash bytes
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

    // Çıktı dosyasını açıyoruz
    final sink = outputFile.openWrite();

    // ignore: prefer_final_locals
    var hashList = <FileHashModel>[];

    // Dizin içindeki tüm dosyaları döngüyle okuyoruz
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final relative = entity.path.substring(dir.path.length + 1);
      final parts = p.split(relative);

      // Skip temp/meta files and our own updater working directory
      final isHashesJson = p.equals(relative, "hashes.json");
      final isDSStore = relative.endsWith(".DS_Store");
      final isInUpdateDir =
          parts.isNotEmpty && parts.first.toLowerCase() == "update";

      if (isHashesJson || isDSStore || isInUpdateDir) {
        continue;
      }

      // Dosyanın hash'ini al (streaming)
      final hash = await getFileHash(entity);
      if (hash.isEmpty) continue;

      final hashObj = FileHashModel(
        filePath: relative,
        calculatedHash: hash,
        length: entity.lengthSync(),
      );
      hashList.add(hashObj);
    }

    // Dosya hash'lerini json formatına çevir
    final jsonStr = jsonEncode(hashList);

    // Çıktı dosyasına yaz
    sink.write(jsonStr);

    // Çıktıyı kaydediyoruz
    await sink.close();
    return outputFile.path;
  } else {
    throw Exception("Desktop Updater: Directory does not exist");
  }
}
