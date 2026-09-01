/// A time-of-day as given in a train schedule ("HH:MM", 24-hour,
/// no timezone - Indian Railways timetables are IST-only). Deliberately
/// not `DateTime`: a schedule time has no date of its own, and pairing
/// it with a fake date would misrepresent the source data.
final class RailwayTime implements Comparable<RailwayTime> {
  const RailwayTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  /// Minutes since 00:00, for ordering/arithmetic within a single
  /// service day. Does not by itself account for [RouteStop.dayOffset]
  /// when comparing stops on different days of a journey.
  int get minutesSinceMidnight => hour * 60 + minute;

  /// Parses a strict "HH:MM" or "HH:MM:SS" 24-hour string as stored by
  /// the database. Returns `null` (never a fabricated time) if [value]
  /// is null, empty, or not a valid time.
  static RailwayTime? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return RailwayTime(hour: hour, minute: minute);
  }

  String toDbString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(RailwayTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RailwayTime && hour == other.hour && minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toDbString();
}
