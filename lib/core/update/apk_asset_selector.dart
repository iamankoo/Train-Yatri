import 'dart:ffi';

import 'github_release.dart';

/// Picks the one release asset (out of an ABI-split release's several
/// APKs) this running app should download - never more than one, per
/// C4 ("do not download unnecessary ABI variants").
///
/// Uses `dart:ffi`'s `Abi.current()` - the ABI this exact running
/// process actually is, with zero extra dependency or platform channel
/// - rather than probing "what could this device support", since a
/// device's installed app already tells us precisely which ABI to keep
/// matching.
abstract final class ApkAssetSelector {
  /// Release APKs are named `train-yatri-vX.Y.Z-<abi>.apk` (see
  /// docs/APK_UPDATE_SYSTEM.md and the release process in
  /// docs/RAILWAY_DATABASE.md's sibling doc) - `<abi>` is one of
  /// `arm64-v8a`, `armeabi-v7a`, `x86_64`, matching
  /// `flutter build apk --split-per-abi`'s own output naming.
  static const _abiToTag = {
    Abi.androidArm64: 'arm64-v8a',
    Abi.androidArm: 'armeabi-v7a',
    Abi.androidX64: 'x86_64',
  };

  /// Documented safe fallback (C4) for a running ABI this project does
  /// not build a matching split for (e.g. 32-bit x86, riscv64) - nearly
  /// every Android device, arm64 included, can execute armeabi-v7a code
  /// via the platform's own backward compatibility, so this is the
  /// asset most likely to actually install and run.
  static const _fallbackTag = 'armeabi-v7a';

  /// `null` if [release] has no `.apk` asset matching either this
  /// process's own ABI or the documented fallback - never guesses at
  /// an unrelated asset.
  static ReleaseAsset? select(GitHubRelease release, {Abi? currentAbi}) {
    final abi = currentAbi ?? Abi.current();
    final preferredTag = _abiToTag[abi] ?? _fallbackTag;

    ReleaseAsset? findByTag(String tag) {
      for (final asset in release.assets) {
        if (asset.name.endsWith('-$tag.apk')) return asset;
      }
      return null;
    }

    return findByTag(preferredTag) ?? findByTag(_fallbackTag);
  }
}
