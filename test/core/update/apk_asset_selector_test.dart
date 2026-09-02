import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/apk_asset_selector.dart';
import 'package:train_yatri/core/update/github_release.dart';

GitHubRelease _releaseWith(List<String> assetNames) {
  return GitHubRelease(
    tagName: 'v0.4.0',
    htmlUrl: 'https://github.com/iamankoo/Train-Yatri/releases/tag/v0.4.0',
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

const _splitAssets = [
  'train-yatri-v0.4.0-arm64-v8a.apk',
  'train-yatri-v0.4.0-armeabi-v7a.apk',
  'train-yatri-v0.4.0-x86_64.apk',
];

void main() {
  test('picks the arm64-v8a asset on an arm64 device', () {
    final release = _releaseWith(_splitAssets);
    final asset = ApkAssetSelector.select(
      release,
      currentAbi: Abi.androidArm64,
    );
    expect(asset?.name, 'train-yatri-v0.4.0-arm64-v8a.apk');
  });

  test('picks the armeabi-v7a asset on a 32-bit arm device', () {
    final release = _releaseWith(_splitAssets);
    final asset = ApkAssetSelector.select(release, currentAbi: Abi.androidArm);
    expect(asset?.name, 'train-yatri-v0.4.0-armeabi-v7a.apk');
  });

  test('picks the x86_64 asset on an x86_64 device', () {
    final release = _releaseWith(_splitAssets);
    final asset = ApkAssetSelector.select(release, currentAbi: Abi.androidX64);
    expect(asset?.name, 'train-yatri-v0.4.0-x86_64.apk');
  });

  test('falls back to the documented safe armeabi-v7a asset for an '
      'unlisted ABI (C4 fallback requirement)', () {
    final release = _releaseWith(_splitAssets);
    final asset = ApkAssetSelector.select(release, currentAbi: Abi.androidIA32);
    expect(asset?.name, 'train-yatri-v0.4.0-armeabi-v7a.apk');
  });

  test('never selects more than one asset', () {
    final release = _releaseWith(_splitAssets);
    final asset = ApkAssetSelector.select(
      release,
      currentAbi: Abi.androidArm64,
    );
    expect(asset, isNotNull);
    // The selector's own return type (a single ReleaseAsset?, not a
    // list) already enforces "at most one" - this just documents the
    // C4 requirement explicitly.
  });

  test('returns null when neither the preferred nor fallback ABI has '
      'a matching asset', () {
    final release = _releaseWith(['train-yatri-v0.4.0-universal.apk']);
    final asset = ApkAssetSelector.select(
      release,
      currentAbi: Abi.androidArm64,
    );
    expect(asset, isNull);
  });

  test('ignores unrelated non-APK / checksum assets', () {
    final release = _releaseWith([
      ...(_splitAssets),
      'train-yatri-v0.4.0-arm64-v8a.apk.sha256',
      'CHECKSUMS.txt',
    ]);
    final asset = ApkAssetSelector.select(
      release,
      currentAbi: Abi.androidArm64,
    );
    expect(asset?.name, 'train-yatri-v0.4.0-arm64-v8a.apk');
  });
}
