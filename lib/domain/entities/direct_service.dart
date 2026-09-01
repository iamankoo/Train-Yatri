import 'route_stop.dart';
import 'train_service.dart';

/// A train that stops at both a "from" and a "to" station, in that
/// order along its route - the result of
/// `RailwayRepository.findDirectServices`.
///
/// [fromStop]/[toStop] are the *specific* route stops matched for this
/// query, not the train's origin/terminus - a long-distance train
/// boarded and alighted at two intermediate stations still produces one
/// [DirectService] using those two stops.
final class DirectService {
  const DirectService({
    required this.train,
    required this.fromStop,
    required this.toStop,
  });

  final TrainService train;
  final RouteStop fromStop;
  final RouteStop toStop;

  /// Journey duration derived from the two stops' own recorded times
  /// (departure at [fromStop], arrival at [toStop]) combined with
  /// [RouteStop.dayOffset] so an overnight journey is never negative.
  /// `null` when either time is missing from the source, or when the
  /// computed duration would be negative (a data inconsistency this
  /// deliberately refuses to paper over with a guess).
  Duration? get journeyDuration {
    final departure = fromStop.departureTime;
    final arrival = toStop.arrivalTime;
    if (departure == null || arrival == null) return null;

    final departureMinutes =
        fromStop.dayOffset * 1440 + departure.minutesSinceMidnight;
    final arrivalMinutes =
        toStop.dayOffset * 1440 + arrival.minutesSinceMidnight;
    final diff = arrivalMinutes - departureMinutes;
    return diff >= 0 ? Duration(minutes: diff) : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectService &&
          train == other.train &&
          fromStop == other.fromStop &&
          toStop == other.toStop;

  @override
  int get hashCode => Object.hash(train, fromStop, toStop);
}
