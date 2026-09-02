import 'package:flutter/material.dart';

import '../../../domain/entities/direct_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/duration_formatter.dart';
import '../../../shared/widgets/train_yatri_card.dart';
import '../../train_details/train_details_screen.dart';

/// One matching train for a From/To search. Shows only what the static
/// timetable actually provides for this specific pair of stops -
/// departure/arrival time and, when both are present, a duration
/// derived from them. Never shows running days, fare, availability,
/// platform or delay, none of which this dataset has.
class TrainResultCard extends StatelessWidget {
  const TrainResultCard({required this.service, super.key});

  final DirectService service;

  @override
  Widget build(BuildContext context) {
    final train = service.train;
    final departure = service.fromStop.departureTime;
    final arrival = service.toStop.arrivalTime;
    final duration = service.journeyDuration;
    final overnight = service.toStop.dayOffset > service.fromStop.dayOffset;

    return Semantics(
      button: true,
      label:
          '${train.number} ${train.name}.'
          '${departure != null ? ' Departs ${departure.toDbString()}.' : ''}'
          '${arrival != null ? ' Arrives ${arrival.toDbString()}${overnight ? ' next day' : ''}.' : ''}',
      child: TrainYatriCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TrainDetailsScreen(train: train)),
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          train.name,
                          style: AppTextStyles.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '#${train.number}',
                          style: AppTextStyles.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (departure != null || arrival != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _TimeColumn(
                      time: departure?.toDbString() ?? '--:--',
                      alignment: CrossAxisAlignment.start,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          if (duration != null)
                            Text(
                              DurationFormatter.hoursMinutes(duration),
                              style: AppTextStyles.label,
                            )
                          else
                            const SizedBox(height: 12),
                          const SizedBox(height: 2),
                          const Divider(),
                        ],
                      ),
                    ),
                    _TimeColumn(
                      time: arrival?.toDbString() ?? '--:--',
                      alignment: CrossAxisAlignment.end,
                      badge: overnight ? '+1 day' : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.time, required this.alignment, this.badge});

  final String time;
  final CrossAxisAlignment alignment;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(time, style: AppTextStyles.title),
        if (badge != null)
          Text(
            badge!,
            style: AppTextStyles.label.copyWith(color: AppColors.warning),
          ),
      ],
    );
  }
}
