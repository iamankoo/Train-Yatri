import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'github_release.dart';

/// A download that failed - offline, GitHub/asset host unreachable, a
/// truncated transfer, or a checksum/size mismatch. Callers (the update
/// UI) catch this and offer Retry (C3) rather than crashing.
final class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ApkDownloadException: $message';
}

/// Downloads one already-selected [ReleaseAsset] with progress, then
/// validates it before handing it back - never hands a caller a file
/// that failed either check.
class ApkDownloader {
  const ApkDownloader({this.timeout = const Duration(minutes: 5)});

  final Duration timeout;

  /// Downloads [asset] into [targetDirectory] (overwriting any partial
  /// file left by a previous failed attempt), reporting
  /// `(receivedBytes, totalBytes)` via [onProgress] as chunks arrive.
  ///
  /// Validates two things once the transfer completes, in order:
  /// 1. The downloaded size matches [ReleaseAsset.sizeBytes] exactly.
  /// 2. If [checksumAssets] contains a `<asset.name>.sha256` entry (a
  ///    plain-text SHA-256 hex digest, the convention this project's
  ///    own release process publishes - see docs/APK_UPDATE_SYSTEM.md),
  ///    the downloaded file's own SHA-256 matches it.
  ///
  /// Throws [ApkDownloadException] - never returns a file that failed
  /// either check - and deletes the bad file rather than leaving it
  /// for a later install attempt to pick up by accident.
  Future<File> download({
    required ReleaseAsset asset,
    required Directory targetDirectory,
    List<ReleaseAsset> checksumAssets = const [],
    void Function(int received, int total)? onProgress,
  }) async {
    await targetDirectory.create(recursive: true);
    final file = File('${targetDirectory.path}/${asset.name}');
    if (file.existsSync()) await file.delete();

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(asset.downloadUrl))
          .timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'TrainYatri-App');
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        await response.drain<void>();
        throw ApkDownloadException(
          'Download failed: HTTP ${response.statusCode}',
        );
      }

      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.timeout(timeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, asset.sizeBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final actualSize = await file.length();
      if (actualSize != asset.sizeBytes) {
        await file.delete();
        throw ApkDownloadException(
          'Downloaded file size ($actualSize bytes) does not match the '
          'expected size (${asset.sizeBytes} bytes) - possibly a '
          'truncated or corrupted download.',
        );
      }

      await _verifyChecksumIfAvailable(file, asset, checksumAssets, client);

      return file;
    } on ApkDownloadException {
      rethrow;
    } on Object catch (error) {
      if (file.existsSync()) await file.delete();
      throw ApkDownloadException('Download failed: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verifyChecksumIfAvailable(
    File file,
    ReleaseAsset asset,
    List<ReleaseAsset> checksumAssets,
    HttpClient client,
  ) async {
    ReleaseAsset? checksumAsset;
    for (final candidate in checksumAssets) {
      if (candidate.name == '${asset.name}.sha256') {
        checksumAsset = candidate;
        break;
      }
    }
    if (checksumAsset == null) return; // nothing published - skip, not fail

    final request = await client
        .getUrl(Uri.parse(checksumAsset.downloadUrl))
        .timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'TrainYatri-App');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      return; // checksum file itself unreachable - don't fail the whole download over it
    }
    final rawChecksum = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    // Conventional `sha256sum` output is "<hex>  <filename>" - only the
    // first whitespace-delimited token is the digest.
    final expectedHex = rawChecksum
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();

    final bytes = await file.readAsBytes();
    final actualHex = sha256.convert(bytes).toString();

    if (actualHex != expectedHex) {
      await file.delete();
      throw const ApkDownloadException(
        'Downloaded file failed SHA-256 checksum verification.',
      );
    }
  }
}
