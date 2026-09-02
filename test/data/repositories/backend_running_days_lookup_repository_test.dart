import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/repositories/backend_running_days_lookup_repository.dart';
import 'package:train_yatri/domain/repositories/running_days_lookup_repository.dart';

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
  test('parses a mixed batch of confirmed/no_data/pending answers', () async {
    late Uri requestedUri;
    final server = await _serverReturning((request) async {
      requestedUri = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'data': {
            '12951': {
              'status': 'confirmed',
              'days': {'monday': true, 'tuesday': false},
            },
            '99999': {'status': 'no_data'},
            '11111': {'status': 'pending'},
          },
        }),
      );
      await request.response.close();
    });

    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await repository.getRunningDays(['12951', '99999', '11111']);

    expect(result['12951']!.status, RunningDaysLookupStatus.confirmed);
    expect(result['12951']!.days, {'monday': true, 'tuesday': false});
    expect(result['99999']!.status, RunningDaysLookupStatus.noData);
    expect(result['99999']!.days, isNull);
    expect(result['11111']!.status, RunningDaysLookupStatus.pending);

    expect(requestedUri.path, '/api/trains/running-days');
    expect(requestedUri.queryParameters['numbers'], '12951,99999,11111');

    await server.close(force: true);
  });

  test('an empty list of train numbers never makes a network call', () async {
    var called = false;
    final server = await _serverReturning((request) async {
      called = true;
      request.response.write('{}');
      await request.response.close();
    });

    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await repository.getRunningDays(const []);

    expect(result, isEmpty);
    expect(called, isFalse);

    await server.close(force: true);
  });

  test('a non-200 response resolves to an empty map, never throws', () async {
    final server = await _serverReturning((request) async {
      request.response.statusCode = 500;
      await request.response.close();
    });

    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await repository.getRunningDays(['12951']);

    expect(result, isEmpty);

    await server.close(force: true);
  });

  test('malformed JSON resolves to an empty map, never throws', () async {
    final server = await _serverReturning((request) async {
      request.response.write('not json{{{');
      await request.response.close();
    });

    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await repository.getRunningDays(['12951']);

    expect(result, isEmpty);

    await server.close(force: true);
  });

  test('an unreachable host resolves to an empty map, never throws', () async {
    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://127.0.0.1:1',
      timeout: const Duration(seconds: 1),
    );
    final result = await repository.getRunningDays(['12951']);

    expect(result, isEmpty);
  });

  test('success:false resolves to an empty map, never throws', () async {
    final server = await _serverReturning((request) async {
      request.response.write(jsonEncode({'success': false}));
      await request.response.close();
    });

    final repository = BackendRunningDaysLookupRepository(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await repository.getRunningDays(['12951']);

    expect(result, isEmpty);

    await server.close(force: true);
  });
}
