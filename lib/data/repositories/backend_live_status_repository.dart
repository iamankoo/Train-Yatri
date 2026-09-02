import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/live_train_status.dart';
import '../../domain/repositories/live_status_repository.dart';

/// Calls only the Train Yatri backend's
/// `GET /api/trains/:trainNumber/live` - never RailRadar directly, and
/// never holds any credential (Block 6's core architectural rule:
/// Flutter -> backend -> RailRadar). [baseUrl] is a safe, non-secret
/// value (see `lib/core/config/env.dart`).
class BackendLiveStatusRepository implements LiveStatusRepository {
  BackendLiveStatusRepository({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 8),
  });

  final String baseUrl;
  final Duration timeout;

  @override
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  }) async {
    final client = HttpClient();
    try {
      final base = Uri.parse(baseUrl);
      final uri = base.replace(
        path:
            '${base.path.replaceAll(RegExp(r'/$'), '')}'
            '/api/trains/$trainNumber/live',
        queryParameters: journeyDate != null ? {'date': journeyDate} : null,
      );

      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        throw const LiveStatusException(
          LiveStatusFailureCategory.unknown,
          "Couldn't load live status.",
        );
      }

      if (response.statusCode == 200 && json['success'] == true) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          return _parseLiveTrainStatus(data);
        }
        throw const LiveStatusException(
          LiveStatusFailureCategory.unknown,
          "Couldn't load live status.",
        );
      }

      throw _exceptionFor(response.statusCode, json);
    } on LiveStatusException {
      rethrow;
    } on TimeoutException {
      throw const LiveStatusException(
        LiveStatusFailureCategory.timeout,
        "Couldn't load live status.",
      );
    } on Object {
      // Any other failure (DNS, connection refused, socket error, TLS
      // failure, offline) - never surfaced with its raw message, per
      // the "no raw provider/backend errors in the UI" rule.
      throw const LiveStatusException(
        LiveStatusFailureCategory.network,
        "Couldn't load live status.",
      );
    } finally {
      client.close(force: true);
    }
  }

  LiveStatusException _exceptionFor(int statusCode, Map<String, dynamic> json) {
    final code = (json['error'] as Map<String, dynamic>?)?['code'] as String?;
    final safeMessage =
        (json['error'] as Map<String, dynamic>?)?['message'] as String? ??
        "Couldn't load live status.";

    final category = switch (code) {
      'not_found' => LiveStatusFailureCategory.notFound,
      'rate_limited' => LiveStatusFailureCategory.rateLimited,
      'provider_unavailable' => LiveStatusFailureCategory.providerUnavailable,
      'provider_not_configured' => LiveStatusFailureCategory.notConfigured,
      'timeout' => LiveStatusFailureCategory.timeout,
      _ => LiveStatusFailureCategory.unknown,
    };
    return LiveStatusException(category, safeMessage);
  }
}

LiveTrainStatus _parseLiveTrainStatus(Map<String, dynamic> json) {
  return LiveTrainStatus(
    trainNumber: json['trainNumber'] as String?,
    trainName: json['trainName'] as String?,
    journeyDate: json['journeyDate'] as String?,
    status: liveStatusCategoryFromWire(json['status'] as String?),
    delayMinutes: (json['delayMinutes'] as num?)?.toInt(),
    lastUpdatedAt: _parseDateTime(json['lastUpdatedAt']),
    isLive: json['isLive'] as bool? ?? false,
    currentLocation: _parseCurrentLocation(
      json['currentLocation'] as Map<String, dynamic>?,
    ),
    previousHalt: _parseHalt(json['previousHalt'] as Map<String, dynamic>?),
    nextHalt: _parseHalt(json['nextHalt'] as Map<String, dynamic>?),
    route: [
      for (final stop in (json['route'] as List? ?? const []))
        _parseRouteStop(stop as Map<String, dynamic>),
    ],
    exceptions: [
      for (final exception in (json['exceptions'] as List? ?? const []))
        _parseException(exception as Map<String, dynamic>),
    ],
  );
}

LiveCurrentLocation? _parseCurrentLocation(Map<String, dynamic>? json) {
  if (json == null) return null;
  return LiveCurrentLocation(
    stationCode: json['stationCode'] as String?,
    sequence: (json['sequence'] as num?)?.toInt(),
    status: json['status'] as String?,
    isHalt: json['isHalt'] as bool?,
    isActualPosition: json['isActualPosition'] as bool?,
    segmentProgress: (json['segmentProgress'] as num?)?.toDouble(),
    speedKmh: (json['speedKmh'] as num?)?.toDouble(),
    bearingDegrees: (json['bearingDegrees'] as num?)?.toInt(),
  );
}

LiveHalt? _parseHalt(Map<String, dynamic>? json) {
  if (json == null) return null;
  return LiveHalt(
    stationCode: json['stationCode'] as String?,
    stationName: json['stationName'] as String?,
    sequence: (json['sequence'] as num?)?.toInt(),
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
  );
}

LiveRouteStop _parseRouteStop(Map<String, dynamic> json) {
  return LiveRouteStop(
    sequence: (json['sequence'] as num?)?.toInt(),
    stationCode: json['stationCode'] as String?,
    stationName: json['stationName'] as String?,
    isHalt: json['isHalt'] as bool?,
    scheduledArrival: _parseDateTime(json['scheduledArrival']),
    scheduledDeparture: _parseDateTime(json['scheduledDeparture']),
    actualArrival: _parseDateTime(json['actualArrival']),
    actualDeparture: _parseDateTime(json['actualDeparture']),
    arrivalDelayMinutes: (json['arrivalDelayMinutes'] as num?)?.toInt(),
    departureDelayMinutes: (json['departureDelayMinutes'] as num?)?.toInt(),
    status: json['status'] as String?,
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    platform: json['platform'] as String?,
  );
}

LiveException _parseException(Map<String, dynamic> json) {
  return LiveException(
    type: liveExceptionTypeFromWire(json['type'] as String?),
    message: json['message'] as String?,
  );
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
