import 'railway_time.dart';

/// One stop of a train's route.
///
/// [dayOffset] is the number of days after the train's origin departure
/// that this stop's [arrivalTime]/[departureTime] fall on - this is
/// what lets the app order and display stops correctly for a train that
/// crosses midnight, without ever inventing a calendar date for a
/// static schedule. A stop with `dayOffset: 1` and an `arrivalTime`
/// earlier in the clock than the previous stop's departure time is
/// still chronologically *after* it, because it is a day later.
final class RouteStop {
  const RouteStop({
    required this.routeStopId,
    required this.trainId,
    required this.stationId,
    required this.stopSequence,
    required this.dayOffset,
    this.arrivalTime,
    this.departureTime,
    this.distanceKm,
  });

  final int routeStopId;
  final int trainId;
  final int stationId;

  /// 1-based order of this stop along the train's route.
  final int stopSequence;

  /// `null` at the origin stop, where there is nothing to arrive from.
  final RailwayTime? arrivalTime;

  /// `null` at the terminus stop, where the train goes no further.
  final RailwayTime? departureTime;

  /// Days elapsed since the train's origin departure (0 for the origin
  /// stop and for any same-day stop).
  final int dayOffset;

  /// Cumulative distance from the origin, in kilometers, when the
  /// source provides it.
  final double? distanceKm;

  bool get isOrigin => arrivalTime == null;
  bool get isTerminus => departureTime == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteStop &&
          routeStopId == other.routeStopId &&
          trainId == other.trainId &&
          stationId == other.stationId &&
          stopSequence == other.stopSequence &&
          arrivalTime == other.arrivalTime &&
          departureTime == other.departureTime &&
          dayOffset == other.dayOffset &&
          distanceKm == other.distanceKm;

  @override
  int get hashCode => Object.hash(
    routeStopId,
    trainId,
    stationId,
    stopSequence,
    arrivalTime,
    departureTime,
    dayOffset,
    distanceKm,
  );

  @override
  String toString() =>
      'RouteStop(#$stopSequence station=$stationId day+$dayOffset)';
}
