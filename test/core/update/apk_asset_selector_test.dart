import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/apk_asset_selector.dart';
import 'package:train_yatri/core/update/github_release.dart';

GitHubRelease _releaseWith(List<String> assetNames) {
  return GitHubRelease(
    tagName: 'v0.5.0',
    htmlUrl: 'https://github.com/iamankoo/Train-Yatri/releases/tag/v0.5.0',
    assets: [
      for (final name in assetNames)
        ReleaseAsset(
          name: name,
          downloadUrl: 'https://example.com/$name',
          sizeBytes: 1000,
        ),
    ],
  );
}

void main() {
  test('picks the single universal APK asset', () {
    final release = _releaseWith([
      'train-yatri-v0.5.0.apk',
      'train-yatri-v0.5.0.apk.sha256',
    ]);
    final asset = ApkAssetSelector.select(release);
    expect(asset?.name, 'train-yatri-v0.5.0.apk');
  });

  test('never selects the checksum file itself', () {
    final release = _releaseWith(['train-yatri-v0.5.0.apk.sha256']);
    expect(ApkAssetSelector.select(release), isNull);
  });

  test('never selects a legacy per-ABI asset (Block 4\'s v0.1.0-v0.4.0 '
      'naming) - only the exact universal-APK filename', () {
    final release = _releaseWith([
      'train-yatri-v0.4.0-arm64-v8a.apk',
      'train-yatri-v0.4.0-armeabi-v7a.apk',
      'train-yatri-v0.4.0-x86_64.apk',
    ]);
    expect(ApkAssetSelector.select(release), isNull);
  });

  test('returns null when the release has no matching asset at all', () {
    final release = _releaseWith(['source-code.zip', 'CHANGELOG.md']);
    expect(ApkAssetSelector.select(release), isNull);
  });

  test('never selects more than one asset even if several exist', () {
    final release = _releaseWith([
      'train-yatri-v0.5.0.apk',
      'train-yatri-v0.5.0.apk.sha256',
      'train-yatri-v0.4.0-arm64-v8a.apk',
    ]);
    final asset = ApkAssetSelector.select(release);
    expect(asset, isNotNull);
    expect(asset!.name, 'train-yatri-v0.5.0.apk');
  });
}
