import 'dart:io';
import 'dart:ui' as ui;

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

  test(
    'icon.png is square (the launcher-icon master must not be distorted)',
    () async {
      // assets/icon.png is generated from a non-square source
      // (352x332) by uniformly scaling to a square - if a future
      // replacement source were dropped in without that scaling step,
      // flutter_launcher_icons would silently stretch it across every
      // Android/iOS density. Decoding the real file and comparing its
      // actual width/height is the only way to catch that; a
      // find-and-decode-through-Image.asset check (as above) wouldn't,
      // since icon.png isn't a bundled asset in the first place.
      final bytes = await File('assets/icon.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(
        frame.image.width,
        frame.image.height,
        reason:
            'assets/icon.png must be square to avoid distortion when '
            'flutter_launcher_icons generates Android/iOS launcher icons',
      );
    },
  );
}
