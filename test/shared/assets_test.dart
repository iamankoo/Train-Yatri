import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the three supplied brand assets actually exist on disk and
/// decode correctly through Flutter's asset pipeline - if one were
/// renamed, deleted, or corrupted, the icon/splash/home screen would
/// silently show a broken-image placeholder in the running app, which a
/// widget test alone (which only checks for text) would not catch.
void main() {
  const assets = [
    'assets/icon.png',
    'assets/splashscreen.png',
    'assets/mainpage.png',
  ];

  for (final path in assets) {
    test('$path exists on disk', () {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    });
  }

  testWidgets('supplied assets decode without error through Image.asset', (
    tester,
  ) async {
    for (final path in assets) {
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
