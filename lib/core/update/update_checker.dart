import 'apk_asset_selector.dart';
import 'release_source.dart';
import 'semantic_version.dart';
import 'update_check_result.dart';
import 'update_info.dart';

/// The whole "is a newer version available" decision (C1), independent
/// of Flutter/platform channels so it's directly unit-testable with a
/// fake [ReleaseSource] - see test/core/update/update_checker_test.dart.
abstract final class UpdateChecker {
  /// The detailed result (see [UpdateCheckResult]) - used where the
  /// difference between "checked, nothing newer" and "the check
  /// failed" actually matters to the caller (Profile's manual "Check
  /// for updates", C8). Never throws.
  static Future<UpdateCheckResult> checkDetailed({
    required String installedVersion,
    required ReleaseSource releaseSource,
  }) async {
    const failed = UpdateCheckResult(status: UpdateCheckStatus.checkFailed);

    final current = SemanticVersion.tryParse(installedVersion);
    if (current == null) return failed;

    final release = await releaseSource.getLatestRelease();
    if (release == null) return failed;

    final latest = SemanticVersion.tryParse(release.tagName);
    if (latest == null) return failed;

    if (latest <= current) {
      return const UpdateCheckResult(status: UpdateCheckStatus.upToDate);
    }

    final asset = ApkAssetSelector.select(release);
    if (asset == null) return failed;

    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      updateInfo: UpdateInfo(
        latestVersion: latest,
        release: release,
        asset: asset,
      ),
    );
  }

  /// `null` for everything [checkDetailed] doesn't consider an actual
  /// update - both "already current" and "the check couldn't complete"
  /// (C6: offline must fail silently, exactly as if there were simply
  /// nothing to offer). Used by the silent background check
  /// (`updateCheckProvider`), which never needs to tell those two
  /// apart.
  static Future<UpdateInfo?> check({
    required String installedVersion,
    required ReleaseSource releaseSource,
  }) async {
    final result = await checkDetailed(
      installedVersion: installedVersion,
      releaseSource: releaseSource,
    );
    return result.status == UpdateCheckStatus.updateAvailable
        ? result.updateInfo
        : null;
  }
}
