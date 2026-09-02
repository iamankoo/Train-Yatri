import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/repositories/backend_live_status_repository.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/domain/repositories/live_status_repository.dart';

/// A minimal real HTTP server standing in for the Train Yatri backend
/// - proves the repository's request shape and JSON parsing against a
/// real socket, never a mocked HttpClient.
Future<HttpServer> _serverReturning(
  FutureOr<void> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await handle(request);
  });
  return server;
}

void main() {
  test('parses a full, real-shaped live status response', () async {
    late Uri requestedUri;
    final server = await _serverReturning((request) async {
      requestedUri = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'data': {
            'trainNumber': '12951',
            'trainName': 'Mumbai Rajdhani',
            'journeyDate': '2026-09-02',
            'status': 'running',
            'delayMinutes': 12,
            'lastUpdatedAt': '2026-09-02T10:00:00+05:30',
            'isLive': true,
            'currentLocation': {
              'stationCode': 'BRC',
              'sequence': 4,
              'status': 'departed',
              'isHalt': false,
              'isActualPosition': true,
              'segmentProgress': 0.4,
              'speedKmh': 82.5,
              'bearingDegrees': 270,
            },
            'previousHalt': {
              'stationCode': 'BRC',
              'stationName': 'Vadodara',
              'sequence': 4,
              'distanceKm': 392.0,
            },
            'nextHalt': {
              'stationCode': 'RTM',
              'stationName': 'Ratlam',
              'sequence': 5,
              'distanceKm': 520.0,
            },
            'route': [
              {
                'sequence': 1,
                'stationCode': 'MMCT',
                'stationName': 'Mumbai Central',
                'scheduledArrival': null,
                'scheduledDeparture': '2026-09-02T17:00:00+05:30',
                'actualArrival': null,
                'actualDeparture': '2026-09-02T17:00:00+05:30',
                'arrivalDelayMinutes': null,
                'departureDelayMinutes': 0,
                'status': 'departed',
                'distanceKm': 0.0,
                'platform': '1',
              },
            ],
            'exceptions': [
              {'type': 'diverted', 'message': 'Diverted via alternate route'},
            ],
          },
        }),
      );
      await request.response.close();
    });

    final repository = BackendLiveStatusRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final status = await repository.getLiveStatus(
      '12951',
      journeyDate: '2026-09-02',
    );

    expect(status.trainNumber, '12951');
    expect(status.trainName, 'Mumbai Rajdhani');
    expect(status.journeyDate, '2026-09-02');
    expect(status.status, LiveStatusCategory.running);
    expect(status.delayMinutes, 12);
    expect(status.isLive, isTrue);
    expect(status.currentLocation!.stationCode, 'BRC');
    expect(status.currentLocation!.speedKmh, 82.5);
    expect(status.previousHalt!.stationName, 'Vadodara');
    expect(status.nextHalt!.stationName, 'Ratlam');
    expect(status.route, hasLength(1));
    expect(status.route.first.platform, '1');
    expect(status.exceptions, hasLength(1));
    expect(status.exceptions.first.type, LiveExceptionType.diverted);

    expect(requestedUri.path, '/api/trains/12951/live');
    expect(requestedUri.queryParameters['date'], '2026-09-02');

    await server.close(force: true);
  });

  test('a null delayMinutes stays null - never coerced to 0', () async {
    final server = await _serverReturning((request) async {
      request.response.write(
        jsonEncode({
          'success': true,
          'data': {
            'trainNumber': '12951',
            'status': 'not_started',
            'delayMinutes': null,
            'isLive': true,
            'route': [],
            'exceptions': [],
          },
        }),
      );
      await request.response.close();
    });

    final repository = BackendLiveStatusRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final status = await repository.getLiveStatus('12951');

    expect(status.delayMinutes, isNull);

    await server.close(force: true);
  });

  test(
    'a 404 maps to LiveStatusFailureCategory.notFound with the safe message',
    () async {
      final server = await _serverReturning((request) async {
        request.response.statusCode = 404;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'not_found',
              'message': "Live status isn't available for this train.",
            },
          }),
        );
        await request.response.close();
      });

      final repository = BackendLiveStatusRepository(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      await expectLater(
        repository.getLiveStatus('99999'),
        throwsA(
          isA<LiveStatusException>()
              .having(
                (e) => e.category,
                'category',
                LiveStatusFailureCategory.notFound,
              )
              .having(
                (e) => e.message,
                'message',
                "Live status isn't available for this train.",
              ),
        ),
      );

      await server.close(force: true);
    },
  );

  test('a 429 maps to rateLimited', () async {
    final server = await _serverReturning((request) async {
      request.response.statusCode = 429;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': false,
          'error': {
            'code': 'rate_limited',
            'message':
                'Live status is temporarily unavailable. Please try again later.',
          },
        }),
      );
      await request.response.close();
    });

    final repository = BackendLiveStatusRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );

    await expectLater(
      repository.getLiveStatus('12951'),
      throwsA(
        isA<LiveStatusException>().having(
          (e) => e.category,
          'category',
          LiveStatusFailureCategory.rateLimited,
        ),
      ),
    );

    await server.close(force: true);
  });

  test(
    'an unreachable host maps to network failure with the safe message',
    () async {
      final repository = BackendLiveStatusRepository(
        baseUrl: 'http://127.0.0.1:1',
        timeout: const Duration(seconds: 1),
      );

      await expectLater(
        repository.getLiveStatus('12951'),
        throwsA(
          isA<LiveStatusException>().having(
            (e) => e.message,
            'message',
            "Couldn't load live status.",
          ),
        ),
      );
    },
  );

  test('malformed JSON never surfaces raw parse-error text', () async {
    final server = await _serverReturning((request) async {
      request.response.write('not json{{{');
      await request.response.close();
    });

    final repository = BackendLiveStatusRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );

    await expectLater(
      repository.getLiveStatus('12951'),
      throwsA(
        isA<LiveStatusException>().having(
          (e) => e.message,
          'message',
          "Couldn't load live status.",
        ),
      ),
    );

    await server.close(force: true);
  });
}
