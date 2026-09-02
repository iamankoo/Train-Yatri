import 'package:flutter/material.dart';

import '../../../domain/entities/route_stop_with_station.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';

/// A railway-style vertical timeline of a train's real, ordered stops -
/// origin down to destination, with a connecting line, per-stop
/// arrival/departure and (only when [RouteStop.dayOffset] actually
/// advances) a "+Nd" badge so an overnight leg reads correctly instead
/// of looking like a same-day time went backwards.
///
/// Shows only what the dataset actually has for each stop - a stop with
/// no recorded time shows "--:--", never a fabricated one.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({required this.stops, super.key});

  final List<RouteStopWithStation> stops;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stops.length; i++)
          _TimelineRow(
            entry: stops[i],
            index: i + 1,
            isFirst: i == 0,
            isLast: i == stops.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.index,
    required this.isFirst,
    required this.isLast,
  });

  final RouteStopWithStation entry;
  final int index;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final stop = entry.stop;
    final station = entry.station;
    final dayBadge = stop.dayOffset > 0 ? '+${stop.dayOffset}d' : null;

    final semanticsParts = <String>[
      'Stop $index: ${station.name} (${station.code}).',
      if (stop.arrivalTime != null)
        'Arrives ${stop.arrivalTime!.toDbString()}${dayBadge != null ? ' $dayBadge' : ''}.',
      if (stop.departureTime != null)
        'Departs ${stop.departureTime!.toDbString()}${dayBadge != null ? ' $dayBadge' : ''}.',
      if (stop.distanceKm != null)
        '${_formatDistance(stop.distanceKm!)} from origin.',
    ];

    return Semantics(
      label: semanticsParts.join(' '),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimelineRail(isFirst: isFirst, isLast: isLast),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station.name,
                            style: (isFirst || isLast)
                                ? AppTextStyles.title
                                : AppTextStyles.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            [
                              station.code,
                              if (stop.distanceKm != null)
                                _formatDistance(stop.distanceKm!),
                            ].join(' · '),
                            style: AppTextStyles.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _TimeBlock(
                      arrival: stop.arrivalTime?.toDbString(),
                      departure: stop.departureTime?.toDbString(),
                      dayBadge: dayBadge,
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

  String _formatDistance(double km) =>
      '${km == km.roundToDouble() ? km.toInt() : km.toStringAsFixed(1)} km';
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.isFirst, required this.isLast});

  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      child: Column(
        children: [
          Container(
            width: 2,
            height: 6,
            color: isFirst ? Colors.transparent : AppColors.divider,
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isFirst || isLast)
                  ? AppColors.primary
                  : AppColors.surface,
              border: Border.all(
                color: AppColors.primary,
                width: (isFirst || isLast) ? 0 : 2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({this.arrival, this.departure, this.dayBadge});

  final String? arrival;
  final String? departure;
  final String? dayBadge;

  @override
  Widget build(BuildContext context) {
    if (arrival == null && departure == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (arrival != null) Text('A $arrival', style: AppTextStyles.body),
        if (departure != null) Text('D $departure', style: AppTextStyles.body),
        if (dayBadge != null)
          Text(
            dayBadge!,
            style: AppTextStyles.label.copyWith(color: AppColors.warning),
          ),
      ],
    );
  }
}
