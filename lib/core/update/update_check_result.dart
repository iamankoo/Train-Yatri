import 'update_info.dart';

/// The full outcome of an update check - distinguishes "checked fine,
/// nothing newer" from "the check itself couldn't complete" (offline,
/// GitHub unreachable, malformed release). The silent background check
/// (`UpdateChecker.check`, used by `updateCheckProvider`) deliberately
/// collapses both of those to `null` - they mean the same thing to a
/// user who never asked. A user-initiated manual check (Profile's
/// "Check for updates", C8) needs the distinction so it can say
/// "you're on the latest version" instead of a misleading silence.
enum UpdateCheckStatus { upToDate, updateAvailable, checkFailed }

final class UpdateCheckResult {
  const UpdateCheckResult({required this.status, this.updateInfo})
    : assert(
        (status == UpdateCheckStatus.updateAvailable) == (updateInfo != null),
        'updateInfo must be set if and only if an update is available',
      );

  final UpdateCheckStatus status;

  /// Non-null exactly when [status] is [UpdateCheckStatus.updateAvailable].
  final UpdateInfo? updateInfo;
}
