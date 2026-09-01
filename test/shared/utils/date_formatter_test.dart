import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/shared/utils/date_formatter.dart';

void main() {
  group('DateFormatter.shortDate', () {
    test('pads single-digit days', () {
      expect(DateFormatter.shortDate(DateTime(2026, 9, 2)), '02 Sep, 2026');
    });

    test('does not pad the year', () {
      expect(DateFormatter.shortDate(DateTime(2026, 12, 25)), '25 Dec, 2026');
    });

    test('maps every month index to its abbreviation', () {
      const expected = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      for (var month = 1; month <= 12; month++) {
        final result = DateFormatter.shortDate(DateTime(2026, month, 1));
        expect(result, '01 ${expected[month - 1]}, 2026');
      }
    });
  });
}
