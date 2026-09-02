/// Real-time train position/status (Block 6) - the Flutter-side mirror
/// of the Train Yatri backend's normalized live-status JSON, which is
/// itself normalized from RailRadar's `GET /v1/trains/{number}/live`
/// (see docs/LIVE_STATUS.md). Deliberately shaped field-for-field to
/// match the backend response rather than RailRadar's own raw schema -
/// the backend is the only thing coupled to that, per the project's
/// "backend normalizes, Flutter never talks to the provider" rule.
///
/// Every field the provider might not have supplied is nullable here -
/// `null` always means "not provided," never a guessed/zeroed value.
final class LiveTrainStatus {
  const LiveTrainStatus({
    required this.trainNumber,
    required this.trainName,
    required this.journeyDate,
    required this.status,
    required this.delayMinutes,
    required this.lastUpdatedAt,
    required this.isLive,
    required this.currentLocation,
    required this.previousHalt,
    required this.nextHalt,
    required this.route,
    required this.exceptions,
  });

  final String? trainNumber;
  final String? trainName;

  /// The journey's own start date (RailRadar's `startDate`) - distinct
  /// from "today's calendar date": an overnight train that departed
  /// yesterday still has yesterday's date here, exactly preserving
  /// journey/start-date semantics rather than calendar-date semantics
  /// (Block 6 Part 12).
  final String? journeyDate;

  final LiveStatusCategory status;

  /// Minutes late. `null` means the provider did not supply a delay
  /// figure - never coerced to `0` ("unknown is not zero", Part 18/20).
  final int? delayMinutes;

  final DateTime? lastUpdatedAt;
  final bool isLive;

  final LiveCurrentLocation? currentLocation;
  final LiveHalt? previousHalt;
  final LiveHalt? nextHalt;
  final List<LiveRouteStop> route;
  final List<LiveException> exceptions;
}

/// The provider's own journey-progress category. `unknown` covers both
/// "the provider didn't send a status" and "the provider sent a value
/// this app doesn't recognize" - both are told apart from an app-level
/// failure to load (see `LiveStatusState` in
/// `lib/domain/services/live_status_presentation.dart`), which is a
/// different, unrelated axis.
enum LiveStatusCategory {
  notStarted,
  running,
  departed,
  upcoming,
  arrived,
  completed,
  cancelled,
  unknown,
}

LiveStatusCategory liveStatusCategoryFromWire(String? raw) {
  return switch (raw) {
    'not_started' => LiveStatusCategory.notStarted,
    'running' => LiveStatusCategory.running,
    'departed' => LiveStatusCategory.departed,
    'upcoming' => LiveStatusCategory.upcoming,
    'arrived' => LiveStatusCategory.arrived,
    'completed' => LiveStatusCategory.completed,
    'cancelled' => LiveStatusCategory.cancelled,
    _ => LiveStatusCategory.unknown,
  };
}

/// Where the train actually is right now.
final class LiveCurrentLocation {
  const LiveCurrentLocation({
    required this.stationCode,
    required this.sequence,
    required this.status,
    required this.isHalt,
    required this.isActualPosition,
    required this.segmentProgress,
    required this.speedKmh,
    required this.bearingDegrees,
  });

  final String? stationCode;
  final int? sequence;
  final String? status;

  /// `true` when the train is currently *at* [stationCode]; `false`
  /// when it's between [stationCode] and the next one, in which case
  /// [segmentProgress] is the meaningful field.
  final bool? isHalt;

  /// Whether this is a real tracked position vs. an inferred one -
  /// shown as-is, never upgraded to look more precise than the
  /// provider actually claims.
  final bool? isActualPosition;

  /// 0.0-1.0 progress along the current segment. `null` when not
  /// meaningful (e.g. the train is halted).
  final double? segmentProgress;

  final double? speedKmh;
  final int? bearingDegrees;
}

final class LiveHalt {
  const LiveHalt({
    required this.stationCode,
    required this.stationName,
    required this.sequence,
    required this.distanceKm,
  });

  final String? stationCode;
  final String? stationName;
  final int? sequence;
  final double? distanceKm;
}

final class LiveRouteStop {
  const LiveRouteStop({
    required this.sequence,
    required this.stationCode,
    required this.stationName,
    required this.isHalt,
    required this.scheduledArrival,
    required this.scheduledDeparture,
    required this.actualArrival,
    required this.actualDeparture,
    required this.arrivalDelayMinutes,
    required this.departureDelayMinutes,
    required this.status,
    required this.distanceKm,
    required this.platform,
  });

  final int? sequence;
  final String? stationCode;
  final String? stationName;

  /// Whether this route entry is a real, scheduled stoppage - the
  /// train actually halts here - as opposed to a pass-through point
  /// the route travels via without stopping. A real field RailRadar's
  /// live route reports per stop; `null` when the provider didn't say,
  /// never guessed as true or false.
  final bool? isHalt;

  final DateTime? scheduledArrival;
  final DateTime? scheduledDeparture;
  final DateTime? actualArrival;
  final DateTime? actualDeparture;
  final int? arrivalDelayMinutes;
  final int? departureDelayMinutes;
  final String? status;
  final double? distanceKm;
  final String? platform;
}

enum LiveExceptionType { diverted, cancelled, rescheduled, unknown }

LiveExceptionType liveExceptionTypeFromWire(String? raw) {
  return switch (raw) {
    'diverted' => LiveExceptionType.diverted,
    'cancelled' => LiveExceptionType.cancelled,
    'rescheduled' => LiveExceptionType.rescheduled,
    _ => LiveExceptionType.unknown,
  };
}

/// A serious operational change (Block 6 Part 27) - shown as a compact
/// alert, never buried.
final class LiveException {
  const LiveException({required this.type, required this.message});

  final LiveExceptionType type;
  final String? message;
}
