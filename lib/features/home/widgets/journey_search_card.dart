import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/utils/coming_soon.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/station_field.dart';
import '../../../shared/widgets/train_yatri_card.dart';

/// The primary interaction on Home: From / To / Date / Search.
///
/// Station search and journey search are implemented in later blocks
/// (Block 2 wires up the offline SQLite railway dataset, Block 3 wires
/// up search itself); for now every field is a real, tappable,
/// >=48dp-tall control that is visually and structurally final, but
/// gives honest feedback instead of faking a station picker or a train
/// result. Block 3 connects the real repository straight into
/// [StationField.value] / [onSearch] without any layout change here.
class JourneySearchCard extends StatefulWidget {
  const JourneySearchCard({super.key});

  @override
  State<JourneySearchCard> createState() => _JourneySearchCardState();
}

class _JourneySearchCardState extends State<JourneySearchCard> {
  DateTime _journeyDate = DateTime.now();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _journeyDate.isBefore(firstDate) ? firstDate : _journeyDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 120)),
    );
    if (picked != null && mounted) {
      setState(() => _journeyDate = picked);
    }
  }

  void _stationComingSoon() {
    showComingSoon(context, 'Station search', 'coming in the next block');
  }

  @override
  Widget build(BuildContext context) {
    return TrainYatriCard(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.centerRight,
            children: [
              Column(
                children: [
                  StationField(
                    icon: Icons.trip_origin,
                    label: 'From',
                    value: 'Select source station',
                    onTap: _stationComingSoon,
                  ),
                  const Divider(),
                  StationField(
                    icon: Icons.location_on_outlined,
                    label: 'To',
                    value: 'Select destination station',
                    onTap: _stationComingSoon,
                  ),
                ],
              ),
              Positioned(
                right: 0,
                child: _SwapButton(
                  onTap: () => showComingSoon(context, 'Swap stations'),
                ),
              ),
            ],
          ),
          const Divider(),
          DateField(date: _journeyDate, onTap: _pickDate),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Search Trains',
            icon: Icons.search_rounded,
            onPressed: () => showComingSoon(
              context,
              'Train search',
              'coming in a future block',
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Swap source and destination stations',
      child: Material(
        color: AppColors.iconChipBackground,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                Icons.swap_vert_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
