import "dart:async";
import "dart:convert";

import "package:desktop_updater/src/app_archive.dart";
import "package:http/http.dart" as http;
import "package:flutter_test/flutter_test.dart";

const _runNetworkTests = bool.fromEnvironment(
  "RUN_NETWORK_TESTS",
  defaultValue: false,
);

const _archiveUrls = <String>[
  "https://downloads.racingview.app/updates/app-archive.json",
  "https://downloads.racingview.app/updates/beta-app-archive.json",
];

void main() {
  group("remote app archives", () {
    for (final url in _archiveUrls) {
      test(
        "is reachable and parseable: $url",
        () async {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 20));

          expect(response.statusCode, 200);

          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final archive = AppArchiveModel.fromJson(data);

          expect(archive.appName.trim().isNotEmpty, isTrue);
          expect(archive.items, isNotEmpty);

          for (final item in archive.items) {
            expect(item.version.trim().isNotEmpty, isTrue);
            expect(item.shortVersion, greaterThan(0));
            expect(item.platform.trim().isNotEmpty, isTrue);
            expect(item.url.trim().isNotEmpty, isTrue);
            expect(item.changes, isNotNull);
          }
        },
        skip: !_runNetworkTests,
        tags: const ["network"],
      );
    }
  });
}
