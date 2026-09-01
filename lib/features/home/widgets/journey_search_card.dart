import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/recent_searches_providers.dart';
import '../../../domain/entities/recent_search.dart';
import '../../../domain/entities/station.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/station_field.dart';
import '../../../shared/widgets/train_yatri_card.dart';
import '../../search/journey_search_state.dart';
import '../../search/search_results_screen.dart';
import '../../search/station_picker_screen.dart';

/// The primary interaction on Home: From / To / Date / Search.
///
/// Station selection, journey date and the resulting search all run for
/// real against the offline SQLite railway database (see
/// `JourneySearchController` / `RailwayRepository`) - nothing here is a
/// placeholder any more.
class JourneySearchCard extends ConsumerWidget {
  const JourneySearchCard({super.key});

  Future<void> _pickStation(
    BuildContext context,
    WidgetRef ref, {
    required String fieldLabel,
    required void Function(Station station) onPicked,
  }) async {
    final station = await Navigator.of(context).push<Station>(
      MaterialPageRoute(
        builder: (_) => StationPickerScreen(fieldLabel: fieldLabel),
      ),
    );
    if (station != null) onPicked(station);
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(firstDate) ? firstDate : current,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 120)),
    );
    if (picked != null) {
      ref.read(journeySearchControllerProvider.notifier).setDate(picked);
    }
  }

  Future<void> _search(BuildContext context, WidgetRef ref) async {
    final state = ref.read(journeySearchControllerProvider);
    if (state.hasSameStationSelected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('From and To stations must be different.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    if (!state.isValid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Select both From and To stations to search.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final from = state.from!;
    final to = state.to!;
    final date = state.date;

    unawaited(_saveRecentSearch(ref, from, to, date));

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(from: from, to: to, date: date),
      ),
    );
  }

  Future<void> _saveRecentSearch(
    WidgetRef ref,
    Station from,
    Station to,
    DateTime date,
  ) async {
    final repository = await ref.read(recentSearchesRepositoryProvider.future);
    await repository.save(
      RecentSearch(
        fromCode: from.code,
        fromName: from.name,
        toCode: to.code,
        toName: to.name,
        date: date,
        searchedAt: DateTime.now(),
      ),
    );
    ref.invalidate(recentSearchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(journeySearchControllerProvider);
    final controller = ref.read(journeySearchControllerProvider.notifier);

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
                    value: state.from == null
                        ? 'Select source station'
                        : '${state.from!.name} (${state.from!.code})',
                    isPlaceholder: state.from == null,
                    onTap: () => _pickStation(
                      context,
                      ref,
                      fieldLabel: 'From',
                      onPicked: (station) => controller.setFrom(station),
                    ),
                  ),
                  const Divider(),
                  StationField(
                    icon: Icons.location_on_outlined,
                    label: 'To',
                    value: state.to == null
                        ? 'Select destination station'
                        : '${state.to!.name} (${state.to!.code})',
                    isPlaceholder: state.to == null,
                    onTap: () => _pickStation(
                      context,
                      ref,
                      fieldLabel: 'To',
                      onPicked: (station) => controller.setTo(station),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 0,
                child: _SwapButton(
                  enabled: state.from != null || state.to != null,
                  onTap: controller.swap,
                ),
              ),
            ],
          ),
          const Divider(),
          DateField(
            date: state.date,
            onTap: () => _pickDate(context, ref, state.date),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Search Trains',
            icon: Icons.search_rounded,
            onPressed: () => _search(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Swap source and destination stations',
      child: Material(
        color: AppColors.iconChipBackground,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
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
