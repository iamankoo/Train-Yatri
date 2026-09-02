// Deep coverage of startUpdateDownloadFlow's downloading/progress/error/
// retry/install-handoff state machine (C3), using an injected fake
// ApkDownloader/ApkInstaller instead of real network I/O -
// `flutter_test`'s TestWidgetsFlutterBinding makes every real HttpClient
// in a widget test return HTTP 400 unconditionally, so a genuine
// download cannot be exercised here; see
// test/core/update/apk_downloader_test.dart for real-network coverage
// (plain `test()`, not `testWidgets()`, so it's unaffected by that).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/apk_downloader.dart';
import 'package:train_yatri/core/update/github_release.dart';
import 'package:train_yatri/core/update/semantic_version.dart';
import 'package:train_yatri/core/update/update_info.dart';
import 'package:train_yatri/features/update/widgets/update_download_dialog.dart';
import 'package:train_yatri/services/update/apk_installer.dart';

class _FakeApkDownloader extends ApkDownloader {
  const _FakeApkDownloader({
    this.fileToReturn,
    this.exceptionToThrow,
    this.progressSteps = const [],
  });

  final File? fileToReturn;
  final ApkDownloadException? exceptionToThrow;
  final List<(int, int)> progressSteps;

  @override
  Future<File> download({
    required ReleaseAsset asset,
    required Directory targetDirectory,
    List<ReleaseAsset> checksumAssets = const [],
    void Function(int received, int total)? onProgress,
  }) async {
    for (final (received, total) in progressSteps) {
      onProgress?.call(received, total);
    }
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return fileToReturn!;
  }
}

/// Fails the first [failFirstAttempts] calls with [ApkDownloadException],
/// then succeeds with [fileToReturn] - models "Retry actually retries".
class _FlakyFakeApkDownloader extends ApkDownloader {
  _FlakyFakeApkDownloader({
    required this.fileToReturn,
    required this.failFirstAttempts,
  });

  final File fileToReturn;
  final int failFirstAttempts;
  int attempts = 0;

  @override
  Future<File> download({
    required ReleaseAsset asset,
    required Directory targetDirectory,
    List<ReleaseAsset> checksumAssets = const [],
    void Function(int received, int total)? onProgress,
  }) async {
    attempts++;
    if (attempts <= failFirstAttempts) {
      throw const ApkDownloadException('network error');
    }
    return fileToReturn;
  }
}

class _NeverCompletingApkDownloader extends ApkDownloader {
  const _NeverCompletingApkDownloader();

  @override
  Future<File> download({
    required ReleaseAsset asset,
    required Directory targetDirectory,
    List<ReleaseAsset> checksumAssets = const [],
    void Function(int received, int total)? onProgress,
  }) {
    return Completer<File>().future;
  }
}

class _FakeApkInstaller extends ApkInstaller {
  const _FakeApkInstaller({this.onInstall});
  final void Function(File file)? onInstall;

  @override
  Future<void> install(File apkFile) async {
    onInstall?.call(apkFile);
  }
}

final _updateInfo = UpdateInfo(
  latestVersion: const SemanticVersion(major: 9, minor: 9, patch: 9),
  release: const GitHubRelease(tagName: 'v9.9.9', htmlUrl: '', assets: []),
  asset: const ReleaseAsset(
    name: 'train-yatri-v9.9.9-armeabi-v7a.apk',
    downloadUrl: 'https://example.com/apk',
    sizeBytes: 200,
  ),
);

Widget _harness({
  required ApkDownloader downloader,
  required ApkInstaller installer,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => startUpdateDownloadFlow(
              context,
              _updateInfo,
              downloader: downloader,
              installer: installer,
              targetDirectory: Directory.systemTemp,
            ),
            child: const Text('start'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('update_dialog_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets(
    'a successful download hands off to the installer and closes the dialog',
    (tester) async {
      final apkFile = File('${tempDir.path}/fake.apk')
        ..writeAsStringSync('fake apk bytes');
      File? installedFile;

      await tester.pumpWidget(
        _harness(
          downloader: _FakeApkDownloader(
            fileToReturn: apkFile,
            progressSteps: const [(50, 200), (200, 200)],
          ),
          installer: _FakeApkInstaller(
            onInstall: (file) => installedFile = file,
          ),
        ),
      );

      await tester.tap(find.text('start'));
      await tester.pump();
      expect(find.text('Downloading update'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('Downloading update'), findsNothing);
      expect(installedFile?.path, apkFile.path);
    },
  );

  testWidgets('shows progress as it is reported by the downloader', (
    tester,
  ) async {
    final apkFile = File('${tempDir.path}/fake.apk')
      ..writeAsStringSync('fake apk bytes');
    final progressController = StreamController<(int, int)>();
    addTearDown(progressController.close);

    // A 5 MB asset so 0 MB / 1 MB / 5 MB received are all visibly
    // distinct formatted values (unlike the 200-byte shared
    // _updateInfo, where every plausible progress value rounds to the
    // same "0.0 MB").
    const fiveMbAsset = ReleaseAsset(
      name: 'train-yatri-v9.9.9-armeabi-v7a.apk',
      downloadUrl: 'https://example.com/apk',
      sizeBytes: 5 * 1024 * 1024,
    );
    final updateInfo = UpdateInfo(
      latestVersion: const SemanticVersion(major: 9, minor: 9, patch: 9),
      release: const GitHubRelease(tagName: 'v9.9.9', htmlUrl: '', assets: []),
      asset: fiveMbAsset,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => startUpdateDownloadFlow(
                  context,
                  updateInfo,
                  downloader: _StreamedFakeApkDownloader(
                    fileToReturn: apkFile,
                    progress: progressController.stream,
                  ),
                  installer: const _FakeApkInstaller(),
                  targetDirectory: tempDir,
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pump();
    expect(find.text('0.0 / 5.0 MB'), findsOneWidget);

    progressController.add((1024 * 1024, 5 * 1024 * 1024));
    await tester.pump();
    expect(find.text('1.0 / 5.0 MB'), findsOneWidget);
    expect(find.text('0.0 / 5.0 MB'), findsNothing);
    // Deliberately left open (never closed within the test body): the
    // download Future is meant to stay pending here so the dialog
    // doesn't try to pop/install mid-assertion - addTearDown above
    // closes it once the test itself is done.
  });

  testWidgets('a failed download shows an error with Retry, and Retry actually '
      'retries and succeeds', (tester) async {
    final apkFile = File('${tempDir.path}/fake.apk')
      ..writeAsStringSync('fake apk bytes');
    final downloader = _FlakyFakeApkDownloader(
      fileToReturn: apkFile,
      failFirstAttempts: 1,
    );

    await tester.pumpWidget(
      _harness(downloader: downloader, installer: const _FakeApkInstaller()),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.textContaining('network error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(downloader.attempts, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Downloading update'), findsNothing);
    expect(downloader.attempts, 2);
  });

  testWidgets('Cancel on a failed download closes the dialog', (tester) async {
    await tester.pumpWidget(
      _harness(
        downloader: const _FakeApkDownloader(
          exceptionToThrow: ApkDownloadException('network error'),
        ),
        installer: const _FakeApkInstaller(),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.textContaining('network error'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Downloading update'), findsNothing);
  });

  testWidgets('the dialog cannot be dismissed by tapping the barrier while '
      'downloading (C3: no silent bypass mid-transfer)', (tester) async {
    await tester.pumpWidget(
      _harness(
        downloader: const _NeverCompletingApkDownloader(),
        installer: const _FakeApkInstaller(),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pump();
    expect(find.text('Downloading update'), findsOneWidget);

    // Tap outside the dialog (top-left corner, well clear of it).
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(find.text('Downloading update'), findsOneWidget);
  });
}

class _StreamedFakeApkDownloader extends ApkDownloader {
  _StreamedFakeApkDownloader({
    required this.fileToReturn,
    required this.progress,
  });

  final File fileToReturn;
  final Stream<(int, int)> progress;

  @override
  Future<File> download({
    required ReleaseAsset asset,
    required Directory targetDirectory,
    List<ReleaseAsset> checksumAssets = const [],
    void Function(int received, int total)? onProgress,
  }) async {
    final completer = Completer<File>();
    final subscription = progress.listen((event) {
      onProgress?.call(event.$1, event.$2);
    }, onDone: () => completer.complete(fileToReturn));
    unawaited(completer.future.whenComplete(subscription.cancel));
    return completer.future;
  }
}
