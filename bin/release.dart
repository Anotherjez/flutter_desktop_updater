import "dart:convert";
import "dart:io";

import "package:path/path.dart" as path;
import "package:pubspec_parse/pubspec_parse.dart";

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    exit(1);
  }

  final platform = args[0];

  if (platform != "macos" && platform != "windows" && platform != "linux") {
    exit(1);
  }

  final pubspec = File("pubspec.yaml").readAsStringSync();
  final parsed = Pubspec.parse(pubspec);

  /// Only base version 1.0.0
  final buildName =
      "${parsed.version?.major}.${parsed.version?.minor}.${parsed.version?.patch}";
  final buildNumber = parsed.version?.build.firstOrNull.toString();

  final appNamePubspec = parsed.name;

  // Get flutter path
  final flutterPath = Platform.environment["FLUTTER_ROOT"];

  if (flutterPath == null || flutterPath.isEmpty) {
    exit(1);
  }

  // Print current working directory

  // Determine the Flutter executable based on the platform
  var flutterExecutable = "flutter";
  if (Platform.isWindows) {
    flutterExecutable += ".bat";
  }

  final flutterBinPath = path.join(flutterPath, "bin", flutterExecutable);

  if (!File(flutterBinPath).existsSync()) {
    exit(1);
  }

  final buildCommand = [
    flutterBinPath,
    "build",
    platform,
    "--dart-define",
    "FLUTTER_BUILD_NAME=$buildName",
    "--dart-define",
    "FLUTTER_BUILD_NUMBER=$buildNumber",
  ];

  // Replace Process.run with Process.start to handle real-time output
  final process =
      await Process.start(buildCommand.first, buildCommand.sublist(1));

  process.stderr.transform(utf8.decoder).listen((data) {
    stderr.writeln(data);
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln("Build failed with exit code $exitCode");
    exit(1);
  }

  late Directory buildDir;

  // Determine the build directory based on the platform
  if (platform == "windows") {
    buildDir = Directory(
      path.join("build", "windows", "x64", "runner", "Release"),
    );
  } else if (platform == "macos") {
    buildDir = Directory(
      path.join(
        "build",
        "macos",
        "Build",
        "Products",
        "Release",
        "$appNamePubspec.app",
      ),
    );
  } else if (platform == "linux") {
    buildDir = Directory(
      path.join("build", "linux", "x64", "release", "bundle"),
    );
  }

  if (!buildDir.existsSync()) {
    exit(1);
  }

  final distPath = platform == "windows"
      ? path.join(
          "dist",
          buildNumber,
          "$appNamePubspec-$buildName+$buildNumber-$platform",
        )
      : platform == "macos"
          ? path.join(
              "dist",
              buildNumber,
              "$appNamePubspec-$buildName+$buildNumber-$platform",
              "$appNamePubspec.app",
            )
          : path.join(
              "dist",
              buildNumber,
              "$appNamePubspec-$buildName+$buildNumber-$platform",
            );

  final distDir = Directory(distPath);
  if (distDir.existsSync()) {
    distDir.deleteSync(recursive: true);
  }

  // Copy buildDir to distPath
  await copyDirectory(buildDir, Directory(distPath));
}

// Helper function to copy directories recursively
Future<void> copyDirectory(Directory source, Directory destination) async {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }

  await for (final entity in source.list(recursive: true)) {
    if (entity is File) {
      final relativePath = path.relative(entity.path, from: source.path);
      final newPath = path.join(destination.path, relativePath);
      await Directory(path.dirname(newPath)).create(recursive: true);
      await entity.copy(newPath);
    }
  }
}
