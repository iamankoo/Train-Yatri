import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/services/railway_normalization.dart';

void main() {
  group('normalizeName', () {
    test('lowercases', () {
      expect(RailwayNormalization.normalizeName('New Delhi'), 'new delhi');
    });

    test('trims leading/trailing whitespace', () {
      expect(RailwayNormalization.normalizeName('  New Delhi  '), 'new delhi');
    });

    test('collapses internal whitespace runs', () {
      expect(RailwayNormalization.normalizeName('New    Delhi'), 'new delhi');
    });

    test('collapses tabs and newlines too', () {
      expect(RailwayNormalization.normalizeName('New\tDelhi\n'), 'new delhi');
    });
  });

  group('normalizeCode', () {
    test('uppercases', () {
      expect(RailwayNormalization.normalizeCode('ndls'), 'NDLS');
    });

    test('trims but does not collapse internal characters', () {
      expect(RailwayNormalization.normalizeCode('  ndls  '), 'NDLS');
    });

    test('is stable for an already-normalized code', () {
      expect(RailwayNormalization.normalizeCode('NDLS'), 'NDLS');
    });
  });
}
