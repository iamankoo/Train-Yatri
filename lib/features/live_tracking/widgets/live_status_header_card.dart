import 'package:flutter/material.dart';

import '../../../domain/entities/live_train_status.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/date_formatter.dart';
import 'live_delay_indicator.dart';

/// The compact live-status summary shown at the top of both
/// `LiveStatusScreen` and (when a train is actually running) Train
/// Details: a status pill, the delay indicator, current location, and
/// when it was last updated. Deliberately does not repeat the train
/// name/number - the screen's own header already shows that.
class LiveStatusHeaderCard extends StatelessWidget {
  const LiveStatusHeaderCard({required this.status, super.key});

  final LiveTrainStatus status;

  String get _statusLabel => switch (status.status) {
    LiveStatusCategory.notStarted => 'Not started',
    LiveStatusCategory.running => 'Running',
    LiveStatusCategory.departed => 'Departed',
    LiveStatusCategory.upcoming => 'Upcoming',
    LiveStatusCategory.arrived => 'Arrived',
    LiveStatusCategory.completed => 'Completed',
    LiveStatusCategory.cancelled => 'Cancelled',
    LiveStatusCategory.unknown => 'Status unknown',
  };

  Color get _statusColor => switch (status.status) {
    LiveStatusCategory.cancelled => AppColors.error,
    LiveStatusCategory.running ||
    LiveStatusCategory.departed => AppColors.primary,
    LiveStatusCategory.arrived ||
    LiveStatusCategory.completed => AppColors.success,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final location = status.currentLocation;
    final locationLabel = location == null
        ? null
        : [
            (location.isHalt ?? false)
                ? 'At ${location.stationCode ?? 'unknown station'}'
                : 'Near ${location.stationCode ?? 'unknown station'}',
            if (location.speedKmh != null) '${location.speedKmh!.round()} km/h',
          ].join(', ');
    final nextLabel = status.nextHalt == null
        ? null
        : status.nextHalt!.stationName ?? status.nextHalt!.stationCode;

    return Semantics(
      label: [
        'Live status: $_statusLabel.',
        if (locationLabel != null) '$locationLabel.',
      ].join(' '),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      _statusLabel.toUpperCase(),
                      style: AppTextStyles.label.copyWith(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                LiveDelayIndicator(delayMinutes: status.delayMinutes),
              ],
            ),
            if (locationLabel != null || nextLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        ?locationLabel,
                        if (nextLabel != null) 'Next $nextLabel',
                      ].join('  ·  '),
                      style: AppTextStyles.bodyMuted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (status.lastUpdatedAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Updated ${DateFormatter.time(status.lastUpdatedAt!)}',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
