import 'data_confidence.dart';

/// A train's weekly operating calendar.
///
/// When [confidence] is [DataConfidence.unknown], the UI must not
/// present the day flags below as a confirmed weekly schedule (e.g. "we
/// don't have confirmed operating days for this service" rather than
/// implying it runs - or doesn't run - on a given day).
final class RunningDays {
  const RunningDays({
    required this.trainId,
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
    this.confidence = DataConfidence.unknown,
  });

  final int trainId;

  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;

  final DataConfidence confidence;

  /// Operates on [weekday] per `DateTime.weekday` (1 = Monday ... 7 =
  /// Sunday). Only meaningful when [confidence] is
  /// [DataConfidence.confirmed] - callers must check that themselves,
  /// this does not silently guess.
  bool operatesOnWeekday(int weekday) => switch (weekday) {
    DateTime.monday => monday,
    DateTime.tuesday => tuesday,
    DateTime.wednesday => wednesday,
    DateTime.thursday => thursday,
    DateTime.friday => friday,
    DateTime.saturday => saturday,
    DateTime.sunday => sunday,
    _ => throw ArgumentError.value(weekday, 'weekday', 'must be 1-7'),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunningDays &&
          trainId == other.trainId &&
          monday == other.monday &&
          tuesday == other.tuesday &&
          wednesday == other.wednesday &&
          thursday == other.thursday &&
          friday == other.friday &&
          saturday == other.saturday &&
          sunday == other.sunday &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(
    trainId,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
    confidence,
  );
}
