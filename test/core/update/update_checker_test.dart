import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/github_release.dart';
import 'package:train_yatri/core/update/release_source.dart';
import 'package:train_yatri/core/update/update_check_result.dart';
import 'package:train_yatri/core/update/update_checker.dart';

class _FakeReleaseSource implements ReleaseSource {
  _FakeReleaseSource(this.release);
  final GitHubRelease? release;

  @override
  Future<GitHubRelease?> getLatestRelease() async => release;
}

const _apkAssets = [
  ReleaseAsset(
    name: 'train-yatri-v0.4.0.apk',
    downloadUrl: 'https://example.com/train-yatri-v0.4.0.apk',
    sizeBytes: 1000,
  ),
];

void main() {
  group('checkDetailed', () {
    test('updateAvailable when the release is genuinely newer', () async {
      final source = _FakeReleaseSource(
        const GitHubRelease(
          tagName: 'v0.4.0',
          htmlUrl: 'https://example.com/release',
          assets: _apkAssets,
        ),
      );
      final result = await UpdateChecker.checkDetailed(
        installedVersion: '0.3.0',
        releaseSource: source,
      );

      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.updateInfo!.latestVersion.toString(), '0.4.0');
      expect(result.updateInfo!.asset.name, 'train-yatri-v0.4.0.apk');
    });

    test('upToDate when the installed version equals the release', () async {
      final source = _FakeReleaseSource(
        const GitHubRelease(tagName: 'v0.4.0', htmlUrl: '', assets: _apkAssets),
      );
      final result = await UpdateChecker.checkDetailed(
        installedVersion: '0.4.0',
        releaseSource: source,
      );
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.updateInfo, isNull);
    });

    test('upToDate when the installed version is actually newer than the '
        'release (never offers a downgrade)', () async {
      final source = _FakeReleaseSource(
        const GitHubRelease(tagName: 'v0.3.0', htmlUrl: '', assets: _apkAssets),
      );
      final result = await UpdateChecker.checkDetailed(
        installedVersion: '0.4.0',
        releaseSource: source,
      );
      expect(result.status, UpdateCheckStatus.upToDate);
    });

    test('checkFailed when the release source returns null (offline, '
        'C6)', () async {
      final source = _FakeReleaseSource(null);
      final result = await UpdateChecker.checkDetailed(
        installedVersion: '0.3.0',
        releaseSource: source,
      );
      expect(result.status, UpdateCheckStatus.checkFailed);
      expect(result.updateInfo, isNull);
    });

    test(
      'checkFailed when the release tag is not a parseable version',
      () async {
        final source = _FakeReleaseSource(
          const GitHubRelease(
            tagName: 'not-a-version',
            htmlUrl: '',
            assets: _apkAssets,
          ),
        );
        final result = await UpdateChecker.checkDetailed(
          installedVersion: '0.3.0',
          releaseSource: source,
        );
        expect(result.status, UpdateCheckStatus.checkFailed);
      },
    );

    test('checkFailed when the release has no universal-APK asset (never '
        'never falls back to an unrelated asset)', () async {
      final source = _FakeReleaseSource(
        const GitHubRelease(
          tagName: 'v0.4.0',
          htmlUrl: '',
          assets: [
            ReleaseAsset(
              name: 'source-code.zip',
              downloadUrl: 'https://example.com/source-code.zip',
              sizeBytes: 500,
            ),
          ],
        ),
      );
      final result = await UpdateChecker.checkDetailed(
        installedVersion: '0.3.0',
        releaseSource: source,
      );
      expect(result.status, UpdateCheckStatus.checkFailed);
    });

    test(
      'checkFailed when the installed version itself cannot be parsed',
      () async {
        final source = _FakeReleaseSource(
          const GitHubRelease(
            tagName: 'v0.4.0',
            htmlUrl: '',
            assets: _apkAssets,
          ),
        );
        final result = await UpdateChecker.checkDetailed(
          installedVersion: 'garbage',
          releaseSource: source,
        );
        expect(result.status, UpdateCheckStatus.checkFailed);
      },
    );
  });

  group('check (the silent/background variant)', () {
    test('returns UpdateInfo when an update is available', () async {
      final source = _FakeReleaseSource(
        const GitHubRelease(tagName: 'v0.4.0', htmlUrl: '', assets: _apkAssets),
      );
      final info = await UpdateChecker.check(
        installedVersion: '0.3.0',
        releaseSource: source,
      );
      expect(info, isNotNull);
    });

    test('collapses both "up to date" and "check failed" to null - a '
        'caller cannot (and must not need to) tell them apart', () async {
      final upToDate = await UpdateChecker.check(
        installedVersion: '0.4.0',
        releaseSource: _FakeReleaseSource(
          const GitHubRelease(tagName: 'v0.4.0', htmlUrl: '', assets: []),
        ),
      );
      final failed = await UpdateChecker.check(
        installedVersion: '0.4.0',
        releaseSource: _FakeReleaseSource(null),
      );
      expect(upToDate, isNull);
      expect(failed, isNull);
    });
  });
}
