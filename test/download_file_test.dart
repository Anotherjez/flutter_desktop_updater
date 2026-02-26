import "dart:async";
import "dart:convert";
import "dart:io";

import "package:desktop_updater/src/download.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;

void main() {
  group("downloadFile", () {
    late HttpServer server;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp("desktop_updater_test");

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.forEach((request) async {
          if (request.uri.path == "/updates/bin/app.exe") {
            final bytes = utf8.encode("test-binary-content");
            request.response.statusCode = HttpStatus.ok;
            request.response.headers
                .set(HttpHeaders.contentLengthHeader, bytes.length.toString());
            request.response.add(bytes);
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }),
      );
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test("downloads file and normalizes remote Windows path", () async {
      final host = "http://${server.address.host}:${server.port}/updates";
      var callbackCalled = false;
      var lastReceived = 0.0;
      var lastTotal = 0.0;

      await downloadFile(
        host,
        r"bin\app.exe",
        tempDir.path,
        (receivedKB, totalKB) {
          callbackCalled = true;
          lastReceived = receivedKB;
          lastTotal = totalKB;
        },
      );

      final downloaded = File(
        p.join(tempDir.path, "update", "bin", "app.exe"),
      );

      expect(await downloaded.exists(), isTrue);
      expect(await downloaded.readAsString(), equals("test-binary-content"));
      expect(callbackCalled, isTrue);
      expect(lastTotal, greaterThan(0));
      expect(lastReceived, closeTo(lastTotal, 0.001));
    });

    test("throws when server returns non-200", () async {
      final host = "http://${server.address.host}:${server.port}/updates";

      expect(
        () => downloadFile(host, "missing.file", tempDir.path, null),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
