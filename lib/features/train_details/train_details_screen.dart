import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../domain/entities/route_stop_with_station.dart';
import '../../domain/entities/train_service.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/historical_data_notice.dart';
import '../../shared/widgets/loading_state.dart';
import '../../shared/widgets/train_yatri_card.dart';
import 'widgets/route_timeline.dart';

/// The real Train Details screen (Block 4): a train's full, ordered
/// route straight from the offline SQLite database via
/// `RailwayRepository.getRouteWithStations`.
///
/// Shows only what the static Dec-2017 timetable dataset actually
/// contains - stop sequence, station, arrival/departure time, day
/// offset, distance. Deliberately never shows current location, live
/// delay, platform, fare, seat availability, PNR, live ETA or running
/// status - none of that exists in this dataset, and this block is not
/// the one responsible for adding it.
class TrainDetailsScreen extends ConsumerStatefulWidget {
  const TrainDetailsScreen({required this.train, super.key});

  final TrainService train;

  @override
  ConsumerState<TrainDetailsScreen> createState() => _TrainDetailsScreenState();
}

class _TrainDetailsScreenState extends ConsumerState<TrainDetailsScreen> {
  late Future<List<RouteStopWithStation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRoute();
  }

  Future<List<RouteStopWithStation>> _loadRoute() async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    return repository.getRouteWithStations(widget.train.trainId);
  }

  void _retry() => setState(() => _future = _loadRoute());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(train: widget.train),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: HistoricalDataNotice(),
            ),
            Expanded(
              child: FutureBuilder<List<RouteStopWithStation>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingState(message: 'Loading route...');
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message:
                          'Could not load this train\'s route. Please try again.',
                      onRetry: _retry,
                    );
                  }
                  final stops = snapshot.data ?? const [];
                  if (stops.isEmpty) {
                    return const EmptyState(
                      icon: Icons.route_outlined,
                      message: 'No route recorded for this train',
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: TrainYatriCard(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: RouteTimeline(stops: stops),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.train});

  final TrainService train;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          Expanded(
            child: Semantics(
              header: true,
              label: '${train.name}, train number ${train.number}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    train.name,
                    style: AppTextStyles.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('#${train.number}', style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
