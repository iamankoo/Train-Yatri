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

  /// 24-hour "HH:MM", local time - used by Live Status (Block 6) for
  /// `lastUpdatedAt` and scheduled/actual route-stop times, which
  /// already arrive as local `DateTime`s (see
  /// `BackendLiveStatusRepository`'s `.toLocal()` parsing).
  static String time(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// "YYYY-MM-DD" - the exact format the Train Yatri backend (and
  /// RailRadar itself) expects for a journey date
  /// (`validateJourneyDate` on the backend). Uses [date]'s own
  /// year/month/day only - never the current time - so passing a
  /// user-selected journey date always asks Live Status about that
  /// specific date, not "now".
  static String isoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
