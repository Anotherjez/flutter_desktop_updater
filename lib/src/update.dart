import "dart:async";
import "dart:io";

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/download.dart";

/// Modified updateAppFunction to return a stream of UpdateProgress.
/// The stream emits total kilobytes, received kilobytes, and the currently downloading file's name.
Future<Stream<UpdateProgress>> updateAppFunction({
  required String remoteUpdateFolder,
  required List<FileHashModel?> changes,
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

  final responseStream = StreamController<UpdateProgress>();

  try {
    if (await dir.exists()) {
      if (changes.isEmpty) {
        await responseStream.close();
        return responseStream.stream;
      }

      var receivedBytes = 0.0;
      final totalFiles = changes.length;
      var completedFiles = 0;
  final lastPerFile = <String, double>{};

      // Calculate total length in KB
      final totalLengthKB = changes.fold<double>(
        0,
        (previousValue, element) =>
            previousValue + ((element?.length ?? 0) / 1024.0),
      );

      final changesFutureList = <Future<dynamic>>[];

      for (final file in changes) {
        if (file != null) {
          changesFutureList.add(
            downloadFile(
              remoteUpdateFolder,
              file.filePath,
              dir.path,
              (received, total) {
                final prev = lastPerFile[file.filePath] ?? 0.0;
                final delta = received - prev;
                lastPerFile[file.filePath] = received;
                if (delta > 0) {
                  receivedBytes += delta;
                }
                responseStream.add(
                  UpdateProgress(
                    totalBytes: totalLengthKB,
                    receivedBytes: receivedBytes,
                    currentFile: file.filePath,
                    totalFiles: totalFiles,
                    completedFiles: completedFiles,
                  ),
                );
              },
            ).then((_) {
              completedFiles += 1;

              responseStream.add(
                UpdateProgress(
                  totalBytes: totalLengthKB,
                  receivedBytes: receivedBytes,
                  currentFile: file.filePath,
                  totalFiles: totalFiles,
                  completedFiles: completedFiles,
                ),
              );
            }).catchError((error) {
              responseStream.addError(error);
              return null;
            }),
          );
        }
      }

      unawaited(
        Future.wait(changesFutureList).then((_) async {
          await responseStream.close();
        }),
      );

      return responseStream.stream;
    }
  } catch (e) {
    responseStream.addError(e);
    await responseStream.close();
  }

  return responseStream.stream;
}
