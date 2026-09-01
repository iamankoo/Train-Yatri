/// Minimal date formatting helper. A single "DD Mon, YYYY" format is all
/// the Home screen foundation needs right now, so this avoids pulling in
/// the `intl` package before there is a real localization requirement.
abstract final class DateFormatter {
  static const List<String> _months = [
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

  static String shortDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = _months[date.month - 1];
    return '$day $month, ${date.year}';
  }
}
