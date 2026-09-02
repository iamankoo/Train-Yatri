import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/recent_live_trains_providers.dart';
import '../../domain/entities/live_train_status.dart';
import '../../domain/entities/recent_live_train.dart';
import '../../domain/services/live_status_presentation.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/date_formatter.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/loading_state.dart';
import '../../shared/widgets/train_yatri_card.dart';
import 'live_status_controller.dart';
import 'widgets/live_exception_banner.dart';
import 'widgets/live_route_list.dart';

/// Real-time train running status (Block 6) - polls the Train Yatri
/// backend (never RailRadar directly) roughly every 30 seconds while
/// this screen is visible and the app is foregrounded, via
/// [LiveStatusController]. Shows only genuinely-returned data: a
/// missing field is simply omitted, never guessed or defaulted.
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
              child: _Body(
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

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onRetry});

  final LiveStatusState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      LiveStatusLoading() => const LoadingState(
        message: 'Loading live status...',
      ),
      LiveStatusUnavailable(:final message) => ErrorState(
        message: message,
        onRetry: onRetry,
      ),
      LiveStatusAvailable(:final status, :final isRefreshing, :final isStale) =>
        RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isStale) const _StaleNotice(),
                for (final exception in status.exceptions) ...[
                  LiveExceptionBanner(exception: exception),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TrainYatriCard(child: _StatusSummary(status: status)),
                if (status.route.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  TrainYatriCard(
                    child: LiveRouteList(
                      route: status.route,
                      currentLocation: status.currentLocation,
                    ),
                  ),
                ],
                if (isRefreshing) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    };
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        label: 'Showing the last known status - could not refresh',
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Showing the last known status - could not refresh',
                style: AppTextStyles.bodyMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.status});

  final LiveTrainStatus status;

  String get _statusLabel => switch (status.status) {
    LiveStatusCategory.notStarted => 'Not Started',
    LiveStatusCategory.running => 'Running',
    LiveStatusCategory.departed => 'Departed',
    LiveStatusCategory.upcoming => 'Upcoming',
    LiveStatusCategory.arrived => 'Arrived',
    LiveStatusCategory.completed => 'Completed',
    LiveStatusCategory.cancelled => 'Cancelled',
    LiveStatusCategory.unknown => 'Status Unknown',
  };

  Color get _statusColor => switch (status.status) {
    LiveStatusCategory.cancelled => AppColors.error,
    LiveStatusCategory.running ||
    LiveStatusCategory.departed => AppColors.success,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final delay = status.delayMinutes;
    final location = status.currentLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                _statusLabel,
                style: AppTextStyles.label.copyWith(color: _statusColor),
              ),
            ),
            if (delay != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                delay <= 0 ? 'On time' : '$delay min late',
                style: AppTextStyles.bodyMuted,
              ),
            ],
          ],
        ),
        if (location != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: (location.isHalt ?? false)
                ? 'At ${location.stationCode ?? 'unknown station'}'
                : 'Near ${location.stationCode ?? 'unknown station'}',
          ),
        ],
        if (location?.speedKmh != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            icon: Icons.speed_outlined,
            label: '${location!.speedKmh!.round()} km/h',
          ),
        ],
        if (status.nextHalt != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            icon: Icons.arrow_forward_rounded,
            label:
                'Next: ${status.nextHalt!.stationName ?? status.nextHalt!.stationCode ?? 'Unknown'}',
          ),
        ],
        if (status.lastUpdatedAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Updated ${DateFormatter.time(status.lastUpdatedAt!)}',
            style: AppTextStyles.bodyMuted,
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(label, style: AppTextStyles.body)),
      ],
    );
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
