import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the brand assets actually exist on disk, and that the ones
/// the running app actually bundles/displays decode correctly through
/// Flutter's asset pipeline - if one were renamed, deleted, or
/// corrupted, the icon/splash/home screen would silently show a
/// broken-image placeholder in the running app, which a widget test
/// alone (which only checks for text) would not catch.
void main() {
  // Every asset that should exist in the repo, whether or not it's
  // actually bundled into the running app - see pubspec.yaml's own
  // `assets:` comment for why icon.png/mainpage.png/top.png are kept
  // as repo-only design references/generation sources rather than
  // bundled (Block 5, Part 38's 55 MB hard limit).
  const filesOnDisk = [
    'assets/icon.png',
    'assets/icon_display.png',
    'assets/splashscreen.png',
    'assets/mainpage.png',
    'assets/top.png',
  ];

  // Only the assets actually declared under pubspec.yaml's `assets:`
  // list - what Image.asset can actually resolve at runtime (and what
  // this test's own Flutter test asset bundle mirrors).
  const bundledAssets = ['assets/icon_display.png', 'assets/splashscreen.png'];

  for (final path in filesOnDisk) {
    test('$path exists on disk', () {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    });
  }

  testWidgets('bundled assets decode without error through Image.asset', (
    tester,
  ) async {
    for (final path in bundledAssets) {
      await tester.pumpWidget(
        MaterialApp(
          home: Image.asset(
            path,
            errorBuilder: (_, error, _) {
              fail('Failed to decode $path: $error');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  });
}
