import 'dart:convert';
import 'dart:io';

import '../../domain/repositories/running_days_lookup_repository.dart';

/// Calls the Train Yatri backend's
/// `GET /api/trains/running-days?numbers=...` - the only source this
/// app uses for progressively-learned real weekly running-days data
/// (see `docs/RUNNING_DAYS_BACKFILL.md`). Deliberately never throws:
/// this is a purely additive enrichment to Journey Search results, and
/// a failure here must degrade silently to "nothing learned", never
/// break or delay the underlying offline search.
class BackendRunningDaysLookupRepository
    implements RunningDaysLookupRepository {
  BackendRunningDaysLookupRepository({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 6),
  });

  final String baseUrl;
  final Duration timeout;

  @override
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  ) async {
    if (trainNumbers.isEmpty) return const {};

    final client = HttpClient();
    try {
      final base = Uri.parse(baseUrl);
      final uri = base.replace(
        path:
            '${base.path.replaceAll(RegExp(r'/$'), '')}'
            '/api/trains/running-days',
        queryParameters: {'numbers': trainNumbers.join(',')},
      );

      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode != 200) return const {};

      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['success'] != true) {
        return const {};
      }
      final data = json['data'];
      if (data is! Map<String, dynamic>) return const {};

      return {
        for (final entry in data.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: _parseAnswer(entry.value as Map<String, dynamic>),
      };
    } on Object {
      // Offline, timeout, backend unreachable, malformed response -
      // all degrade to "nothing learned this time", never an
      // exception the caller has to handle.
      return const {};
    } finally {
      client.close(force: true);
    }
  }

  RunningDaysAnswer _parseAnswer(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'confirmed' => RunningDaysLookupStatus.confirmed,
      'no_data' => RunningDaysLookupStatus.noData,
      _ => RunningDaysLookupStatus.pending,
    };
    final rawDays = json['days'];
    final days = rawDays is Map<String, dynamic>
        ? {for (final e in rawDays.entries) e.key: e.value == true}
        : null;
    return RunningDaysAnswer(status, days: days);
  }
}
