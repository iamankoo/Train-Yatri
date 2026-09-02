// Exercises ApkDownloader against a real local HTTP server (dart:io's
// own HttpServer, bound to loopback) rather than a mocked HTTP client -
// so what's actually tested is the real byte-stream/progress/validation
// behavior, not a hand-written stand-in for it.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/apk_downloader.dart';
import 'package:train_yatri/core/update/github_release.dart';

void main() {
  late HttpServer server;
  late Directory tempDir;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tempDir = Directory.systemTemp.createTempSync('apk_downloader_test_');
  });

  tearDown(() async {
    await server.close(force: true);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String baseUrl(String path) => 'http://127.0.0.1:${server.port}/$path';

  test(
    'downloads the real bytes and reports progress up to the total',
    () async {
      final content = List<int>.generate(50000, (i) => i % 256);
      server.listen((request) async {
        request.response.headers.contentLength = content.length;
        request.response.add(content);
        await request.response.close();
      });

      final progressCalls = <(int, int)>[];
      final downloader = const ApkDownloader();
      final file = await downloader.download(
        asset: ReleaseAsset(
          name: 'train-yatri-test.apk',
          downloadUrl: baseUrl('apk'),
          sizeBytes: content.length,
        ),
        targetDirectory: tempDir,
        onProgress: (received, total) => progressCalls.add((received, total)),
      );

      expect(await file.readAsBytes(), content);
      expect(progressCalls, isNotEmpty);
      expect(progressCalls.last.$1, content.length);
    },
  );

  test('throws ApkDownloadException and deletes the partial file when the '
      'downloaded size does not match the declared size (a truncated '
      'transfer)', () async {
    server.listen((request) async {
      request.response.add(List<int>.filled(10, 1)); // shorter than declared
      await request.response.close();
    });

    final downloader = const ApkDownloader();
    final asset = ReleaseAsset(
      name: 'train-yatri-test.apk',
      downloadUrl: baseUrl('apk'),
      sizeBytes: 999999, // deliberately wrong
    );

    await expectLater(
      downloader.download(asset: asset, targetDirectory: tempDir),
      throwsA(isA<ApkDownloadException>()),
    );
    expect(File('${tempDir.path}/train-yatri-test.apk').existsSync(), isFalse);
  });

  test('throws ApkDownloadException on a non-200 response', () async {
    server.listen((request) async {
      request.response.statusCode = 404;
      await request.response.close();
    });

    final downloader = const ApkDownloader();
    await expectLater(
      downloader.download(
        asset: ReleaseAsset(
          name: 'train-yatri-test.apk',
          downloadUrl: baseUrl('missing'),
          sizeBytes: 10,
        ),
        targetDirectory: tempDir,
      ),
      throwsA(isA<ApkDownloadException>()),
    );
  });

  test('verifies a published SHA-256 checksum asset and accepts a matching '
      'file', () async {
    final content = utf8.encode('a genuine apk\'s worth of bytes');
    final expectedHex = sha256.convert(content).toString();

    server.listen((request) async {
      if (request.uri.path == '/apk') {
        request.response.headers.contentLength = content.length;
        request.response.add(content);
      } else if (request.uri.path == '/apk.sha256') {
        final body = utf8.encode('$expectedHex  train-yatri-test.apk\n');
        request.response.headers.contentLength = body.length;
        request.response.add(body);
      }
      await request.response.close();
    });

    final downloader = const ApkDownloader();
    final asset = ReleaseAsset(
      name: 'train-yatri-test.apk',
      downloadUrl: baseUrl('apk'),
      sizeBytes: content.length,
    );
    final checksumAsset = ReleaseAsset(
      name: 'train-yatri-test.apk.sha256',
      downloadUrl: baseUrl('apk.sha256'),
      sizeBytes: 0,
    );

    final file = await downloader.download(
      asset: asset,
      targetDirectory: tempDir,
      checksumAssets: [checksumAsset],
    );
    expect(await file.readAsBytes(), content);
  });

  test('rejects and deletes a file whose bytes do not match the published '
      'checksum - protects against a corrupted or tampered download', () async {
    final content = utf8.encode('the real bytes');
    const wrongHex =
        '0000000000000000000000000000000000000000000000000000000000000000';

    server.listen((request) async {
      if (request.uri.path == '/apk') {
        request.response.headers.contentLength = content.length;
        request.response.add(content);
      } else if (request.uri.path == '/apk.sha256') {
        final body = utf8.encode('$wrongHex  train-yatri-test.apk\n');
        request.response.headers.contentLength = body.length;
        request.response.add(body);
      }
      await request.response.close();
    });

    final downloader = const ApkDownloader();
    final asset = ReleaseAsset(
      name: 'train-yatri-test.apk',
      downloadUrl: baseUrl('apk'),
      sizeBytes: content.length,
    );
    final checksumAsset = ReleaseAsset(
      name: 'train-yatri-test.apk.sha256',
      downloadUrl: baseUrl('apk.sha256'),
      sizeBytes: 0,
    );

    await expectLater(
      downloader.download(
        asset: asset,
        targetDirectory: tempDir,
        checksumAssets: [checksumAsset],
      ),
      throwsA(isA<ApkDownloadException>()),
    );
    expect(File('${tempDir.path}/train-yatri-test.apk').existsSync(), isFalse);
  });
}
