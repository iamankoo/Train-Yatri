import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/semantic_version.dart';

void main() {
  group('tryParse', () {
    test('parses plain major.minor.patch', () {
      final v = SemanticVersion.tryParse('1.2.3');
      expect(v, const SemanticVersion(major: 1, minor: 2, patch: 3));
    });

    test('tolerates a leading v (GitHub Release tag style)', () {
      final v = SemanticVersion.tryParse('v0.4.0');
      expect(v, const SemanticVersion(major: 0, minor: 4, patch: 0));
    });

    test('strips build metadata (pubspec-style +N)', () {
      final v = SemanticVersion.tryParse('0.4.0+4');
      expect(v, const SemanticVersion(major: 0, minor: 4, patch: 0));
    });

    test('strips a pre-release suffix', () {
      final v = SemanticVersion.tryParse('1.0.0-beta.1');
      expect(v, const SemanticVersion(major: 1, minor: 0, patch: 0));
    });

    test('returns null for garbage input, never a guessed version', () {
      expect(SemanticVersion.tryParse('not-a-version'), isNull);
      expect(SemanticVersion.tryParse('1.2'), isNull);
      expect(SemanticVersion.tryParse(''), isNull);
    });
  });

  group('comparison', () {
    test('major takes precedence', () {
      const a = SemanticVersion(major: 1, minor: 9, patch: 9);
      const b = SemanticVersion(major: 2, minor: 0, patch: 0);
      expect(a < b, isTrue);
    });

    test('minor takes precedence over patch', () {
      const a = SemanticVersion(major: 1, minor: 2, patch: 9);
      const b = SemanticVersion(major: 1, minor: 3, patch: 0);
      expect(a < b, isTrue);
    });

    test('patch is compared last', () {
      const a = SemanticVersion(major: 0, minor: 4, patch: 0);
      const b = SemanticVersion(major: 0, minor: 4, patch: 1);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
    });

    test('equal versions compare equal', () {
      const a = SemanticVersion(major: 0, minor: 4, patch: 0);
      const b = SemanticVersion(major: 0, minor: 4, patch: 0);
      expect(a == b, isTrue);
      expect(a <= b, isTrue);
      expect(a >= b, isTrue);
    });
  });
}
