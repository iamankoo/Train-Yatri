import 'github_release.dart';

/// Picks the one release asset this running app should download.
///
/// From v0.5.0 on, every release publishes exactly one **universal**
/// APK - `train-yatri-vX.Y.Z.apk` - installable on any supported
/// Android device, rather than Block 4's original per-ABI split
/// releases (v0.1.0-v0.4.0's `train-yatri-vX.Y.Z-<abi>.apk` files
/// remain on GitHub Releases as history and are never deleted, but the
/// update checker only ever looks at the *latest* release, which from
/// v0.5.0 on always has just the one asset). See
/// docs/APK_UPDATE_SYSTEM.md for the full rationale.
abstract final class ApkAssetSelector {
  static final _universalApkName = RegExp(r'^train-yatri-v\d+\.\d+\.\d+\.apk$');

  /// `null` if [release] has no asset matching the universal-APK naming
  /// convention exactly - never guesses at an unrelated asset (an old
  /// per-ABI file, a `.sha256` checksum file, a source archive, ...).
  static ReleaseAsset? select(GitHubRelease release) {
    for (final asset in release.assets) {
      if (_universalApkName.hasMatch(asset.name)) return asset;
    }
    return null;
  }
}
