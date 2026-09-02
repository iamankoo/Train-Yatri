import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/update/release_source.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_info.dart';

/// The installed app's own version (versionName), read once per app
/// session and cached by Riverpod like `railwayRepositoryProvider`.
final installedVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Swappable in tests (see `test/core/update/update_checker_test.dart`)
/// for a fake that never touches the network.
final releaseSourceProvider = Provider<ReleaseSource>(
  (ref) => const GitHubReleaseSource(),
);

/// C1's whole "is a newer release available" check. `null` covers every
/// "nothing to offer" case - already current, offline, GitHub
/// unreachable, no matching asset, or even [installedVersionProvider]
/// itself failing (e.g. no platform channel available, as under
/// `flutter test`) - deliberately caught here too, so a version-read
/// failure degrades to "no update" the same way an offline network
/// does, rather than surfacing as an app error (C6's spirit applied
/// beyond just the network call).
///
/// A [FutureProvider] specifically so Home's own startup is never
/// blocked on this (C1) - widgets that don't `ref.watch` this provider
/// are entirely unaffected by how long/whether it resolves.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    final installedVersion = await ref.watch(installedVersionProvider.future);
    final releaseSource = ref.watch(releaseSourceProvider);
    return await UpdateChecker.check(
      installedVersion: installedVersion,
      releaseSource: releaseSource,
    );
  } on Object {
    return null;
  }
});

/// Tracks whether the update-available dialog has already been shown
/// once this app session (C2: "do not repeatedly annoy the user during
/// the same session"). Deliberately in-memory/session-only, not
/// persisted - a fresh app launch is a fresh session, and the check
/// itself re-evaluates "is this still the latest" every time anyway.
final updateDialogShownProvider = StateProvider<bool>((ref) => false);
