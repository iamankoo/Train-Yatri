import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/recent_live_trains_providers.dart';
import '../../domain/entities/recent_live_train.dart';
import '../../domain/services/live_status_presentation.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import 'live_status_controller.dart';
import 'widgets/live_status_body.dart';

/// Real-time train running status (Block 6) - polls the Train Yatri
/// backend (never RailRadar directly) roughly every 30 seconds while
/// this screen is visible and the app is foregrounded, via
/// [LiveStatusController]. Shows only genuinely-returned data: a
/// missing field is simply omitted, never guessed or defaulted.
///
/// Reached from the Live tab (a train number typed by hand) or a
/// recently-viewed train - no journey date context, so [journeyDate]
/// is normally `null` here (RailRadar defaults to "today"). Train
/// Details (`TrainDetailsScreen`) is the entry point that supplies a
/// real searched date; both ultimately render through the same
/// [LiveStatusBody] and [LiveStatusController].
class LiveStatusScreen extends ConsumerWidget {
  const LiveStatusScreen({
    required this.trainNumber,
    this.trainName,
    this.journeyDate,
    super.key,
  });

  final String trainNumber;
  final String? trainName;
  final String? journeyDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = LiveStatusQuery(trainNumber, journeyDate: journeyDate);

    ref.listen<LiveStatusState>(liveStatusControllerProvider(query), (
      previous,
      next,
    ) {
      if (next is LiveStatusAvailable && previous is! LiveStatusAvailable) {
        _saveRecent(ref, next.status.trainName);
      }
    });

    final state = ref.watch(liveStatusControllerProvider(query));
    final headerName =
        trainName ??
        (state is LiveStatusAvailable ? state.status.trainName : null);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(trainNumber: trainNumber, trainName: headerName),
            Expanded(
              child: LiveStatusBody(
                state: state,
                onRetry: () => ref
                    .read(liveStatusControllerProvider(query).notifier)
                    .refreshNow(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRecent(WidgetRef ref, String? name) async {
    final repository = await ref.read(
      recentLiveTrainsRepositoryProvider.future,
    );
    await repository.save(
      RecentLiveTrain(
        trainNumber: trainNumber,
        trainName: name ?? trainName,
        viewedAt: DateTime.now(),
      ),
    );
    ref.invalidate(recentLiveTrainsProvider);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.trainNumber, this.trainName});

  final String trainNumber;
  final String? trainName;

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
              label: trainName == null
                  ? 'Live status, train number $trainNumber'
                  : 'Live status, $trainName, train number $trainNumber',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainName ?? 'Train #$trainNumber',
                    style: AppTextStyles.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (trainName != null)
                    Text('#$trainNumber', style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
