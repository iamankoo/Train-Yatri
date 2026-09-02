import 'dart:io';

import 'package:flutter/services.dart';

/// Hands a downloaded APK file off to Android's own package installer
/// (C3) via a small platform channel
/// (`android/app/.../MainActivity.kt`'s `installApk` handler) - this
/// project deliberately does not depend on a plugin for this single
/// call (see the `path_provider` comment in pubspec.yaml for why).
///
/// This only ever *starts* Android's installer UI; the OS itself is
/// what shows the "Install this app?"/"Allow installs from this
/// source?" confirmation (C3, C5) - nothing here silently installs
/// anything.
class ApkInstaller {
  const ApkInstaller();

  static const _channel = MethodChannel('trainyatri.app/apk_installer');

  /// Throws [PlatformException] if Android's `ACTION_VIEW` intent could
  /// not be started at all (e.g. no activity can handle it) - callers
  /// should show this as a plain error, never retry-loop it silently.
  Future<void> install(File apkFile) async {
    await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
  }
}
