import 'github_release.dart';
import 'semantic_version.dart';

/// The result of a successful update check when a newer release
/// genuinely exists - everything the update dialog and downloader need.
final class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.release,
    required this.asset,
  });

  final SemanticVersion latestVersion;
  final GitHubRelease release;

  /// The one APK asset selected for this device's ABI (or the
  /// documented fallback) - see `ApkAssetSelector`.
  final ReleaseAsset asset;
}
