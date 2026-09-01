import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/entities/railway_time.dart';

void main() {
  group('RailwayTime.tryParse', () {
    test('parses HH:MM', () {
      final t = RailwayTime.tryParse('23:45');
      expect(t, const RailwayTime(hour: 23, minute: 45));
    });

    test('parses HH:MM:SS, ignoring seconds', () {
      final t = RailwayTime.tryParse('06:05:30');
      expect(t, const RailwayTime(hour: 6, minute: 5));
    });

    test('returns null for null input', () {
      expect(RailwayTime.tryParse(null), isNull);
    });

    test('returns null for empty input', () {
      expect(RailwayTime.tryParse(''), isNull);
    });

    test('returns null for garbage input', () {
      expect(RailwayTime.tryParse('not a time'), isNull);
    });

    test('returns null for an out-of-range hour', () {
      expect(RailwayTime.tryParse('24:00'), isNull);
    });

    test('returns null for an out-of-range minute', () {
      expect(RailwayTime.tryParse('10:60'), isNull);
    });
  });

  group('ordering', () {
    test('orders by minutes since midnight', () {
      const early = RailwayTime(hour: 6, minute: 0);
      const late = RailwayTime(hour: 18, minute: 30);
      expect(early.compareTo(late), lessThan(0));
    });

    test('a later clock time on an earlier day is NOT "earlier" by itself - '
        'callers must combine this with RouteStop.dayOffset', () {
      // This documents the contract rather than testing RailwayTime
      // itself: RailwayTime has no notion of day, on purpose.
      const nightDeparture = RailwayTime(hour: 23, minute: 50);
      const earlyMorningArrival = RailwayTime(hour: 0, minute: 10);
      expect(nightDeparture.compareTo(earlyMorningArrival), greaterThan(0));
    });
  });

  test('toDbString pads single digits', () {
    expect(const RailwayTime(hour: 6, minute: 5).toDbString(), '06:05');
  });
}
