import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../domain/repositories/running_days_lookup_repository.dart';
import '../repositories/backend_running_days_lookup_repository.dart';

final runningDaysLookupRepositoryProvider =
    Provider<RunningDaysLookupRepository>((ref) {
      return BackendRunningDaysLookupRepository(baseUrl: Env.apiBaseUrl);
    });
