import 'package:flutter/material.dart';

import '../../../domain/entities/live_train_status.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/date_formatter.dart';

enum _StopProgress { past, current, upcoming }

/// The train's route with live past/current/upcoming progress (Block 6
/// Part 22/23) - past/upcoming is derived from
/// [LiveCurrentLocation.sequence] against each stop's own [sequence]
/// (both real, RailRadar-reported numbers), never guessed from time of
/// day. When [currentLocation] or a stop's sequence is missing, that
/// stop simply shows no progress marker rather than a wrong one.
class LiveRouteList extends StatelessWidget {
  const LiveRouteList({
    required this.route,
    required this.currentLocation,
    super.key,
  });

  final List<LiveRouteStop> route;
  final LiveCurrentLocation? currentLocation;

  _StopProgress? _progressFor(LiveRouteStop stop) {
    final currentSequence = currentLocation?.sequence;
    final stopSequence = stop.sequence;
    if (currentSequence == null || stopSequence == null) return null;
    if (stopSequence < currentSequence) return _StopProgress.past;
    if (stopSequence == currentSequence) return _StopProgress.current;
    return _StopProgress.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < route.length; i++)
          _RouteStopRow(
            stop: route[i],
            progress: _progressFor(route[i]),
            isLast: i == route.length - 1,
          ),
      ],
    );
  }
}

class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({
    required this.stop,
    required this.progress,
    required this.isLast,
  });

  final LiveRouteStop stop;
  final _StopProgress? progress;
  final bool isLast;

  Color get _dotColor => switch (progress) {
    _StopProgress.past => AppColors.success,
    _StopProgress.current => AppColors.primary,
    _StopProgress.upcoming => AppColors.divider,
    null => AppColors.divider,
  };

  @override
  Widget build(BuildContext context) {
    final name = stop.stationName ?? stop.stationCode ?? 'Unknown station';
    final time =
        stop.actualArrival ??
        stop.scheduledArrival ??
        stop.actualDeparture ??
        stop.scheduledDeparture;
    final isCurrent = progress == _StopProgress.current;

    return Semantics(
      label: isCurrent ? '$name, current stop' : name,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: _dotColor,
                      shape: BoxShape.circle,
                      border: isCurrent
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: AppColors.divider),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: isCurrent
                            ? AppTextStyles.title
                            : AppTextStyles.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (time != null)
                      Text(
                        DateFormatter.time(time),
                        style: AppTextStyles.bodyMuted,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
