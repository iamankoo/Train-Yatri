import 'package:flutter/material.dart';

import '../../../domain/entities/connecting_journey.dart';
import '../../../domain/entities/direct_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/duration_formatter.dart';
import '../../../shared/widgets/train_yatri_card.dart';
import '../../train_details/train_details_screen.dart';

/// One one-change journey result: leg A (FROM -> interchange), the
/// interchange itself with the calculated wait, then leg B
/// (interchange -> TO) - Block 5's "Journey Summary" (compact, not
/// overloaded: train numbers/names, the interchange, times where
/// available, wait, and total duration, nothing else).
///
/// Each leg is independently tappable straight into the existing
/// Block 4 Train Details screen for that leg's own train (Block 5,
/// "Train Details Integration": reuse, never duplicate, that screen).
class ConnectingJourneyCard extends StatelessWidget {
  const ConnectingJourneyCard({
    required this.journey,
    required this.date,
    super.key,
  });

  final ConnectingJourney journey;

  /// The searched journey date - threaded to each leg's Train Details
  /// so an automatic Live Status check asks about this exact date.
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return TrainYatriCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegRow(leg: journey.legA, date: date),
          const SizedBox(height: AppSpacing.sm),
          _ChangeAtRow(
            stationName: journey.interchange.name,
            stationCode: journey.interchange.code,
            waitingDuration: journey.waitingDuration,
          ),
          const SizedBox(height: AppSpacing.sm),
          _LegRow(leg: journey.legB, date: date),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1),
          ),
          Semantics(
            label:
                'Total journey time ${DurationFormatter.hoursMinutes(journey.totalDuration)}.',
            child: Text(
              'Total: ${DurationFormatter.hoursMinutes(journey.totalDuration)}',
              style: AppTextStyles.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg, required this.date});

  final DirectService leg;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final train = leg.train;
    final departure = leg.fromStop.departureTime;
    final arrival = leg.toStop.arrivalTime;
    final overnight = leg.toStop.dayOffset > leg.fromStop.dayOffset;

    return Semantics(
      button: true,
      label:
          '${train.number} ${train.name}.'
          '${departure != null ? ' Departs ${departure.toDbString()}.' : ''}'
          '${arrival != null ? ' Arrives ${arrival.toDbString()}${overnight ? ' next day' : ''}.' : ''}',
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrainDetailsScreen(train: train, journeyDate: date),
          ),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      train.name,
                      style: AppTextStyles.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('#${train.number}', style: AppTextStyles.label),
                  ],
                ),
              ),
              if (departure != null)
                Text(departure.toDbString(), style: AppTextStyles.body),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              if (arrival != null)
                Text(arrival.toDbString(), style: AppTextStyles.body),
              if (overnight)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '+1d',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeAtRow extends StatelessWidget {
  const _ChangeAtRow({
    required this.stationName,
    required this.stationCode,
    required this.waitingDuration,
  });

  final String stationName;
  final String stationCode;
  final Duration waitingDuration;

  @override
  Widget build(BuildContext context) {
    final waitLabel = DurationFormatter.compactMinutes(waitingDuration);
    return Semantics(
      label: 'Change at $stationName, $stationCode. Wait $waitLabel.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.iconChipBackground,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.sync_alt_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Change at $stationName ($stationCode)',
                style: AppTextStyles.label.copyWith(color: AppColors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'Wait $waitLabel',
              style: AppTextStyles.label.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
