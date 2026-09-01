import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../domain/entities/station.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/loading_state.dart';

/// Full-screen station search. Pushed with `Navigator.push` (not a
/// named route - it only ever needs to return the picked [Station] to
/// its caller via `Navigator.pop`).
///
/// Every result comes from `RailwayRepository.searchStations`, which
/// runs directly against SQLite - nothing here loads the 8k+ station
/// table into Dart. Queries are debounced and guarded against
/// out-of-order results (a fast typist must never see an older,
/// slower-to-return query's results replace a newer one's).
class StationPickerScreen extends ConsumerStatefulWidget {
  const StationPickerScreen({required this.fieldLabel, super.key});

  /// "From" or "To" - shown in the header so the user always knows
  /// which field they're filling in.
  final String fieldLabel;

  @override
  ConsumerState<StationPickerScreen> createState() =>
      _StationPickerScreenState();
}

class _StationPickerScreenState extends ConsumerState<StationPickerScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _searchGeneration = 0;

  String _query = '';
  bool _loading = false;
  Object? _error;
  List<Station> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(value),
    );
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = await ref.read(railwayRepositoryProvider.future);
      final results = await repository.searchStations(query, limit: 30);
      if (!mounted || generation != _searchGeneration) return; // stale
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
                      textField: true,
                      label: 'Search station for ${widget.fieldLabel}',
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onChanged: _onQueryChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Station name or code',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select ${widget.fieldLabel} station',
                  style: AppTextStyles.label,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        message: 'Type a station name or code to search',
      );
    }
    if (_loading) {
      return const LoadingState(message: 'Searching stations...');
    }
    if (_error != null) {
      return ErrorState(
        message: 'Could not search stations. Please try again.',
        onRetry: () => _runSearch(_query),
      );
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.location_off_outlined,
        message: 'No matching stations found',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _StationResultTile(
        station: _results[index],
        onTap: () => Navigator.of(context).pop(_results[index]),
      ),
    );
  }
}

class _StationResultTile extends StatelessWidget {
  const _StationResultTile({required this.station, required this.onTap});

  final Station station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final location = [
      station.city,
      station.state,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Semantics(
      button: true,
      label:
          '${station.name}, ${station.code}${location.isNotEmpty ? ', $location' : ''}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: AppTextStyles.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location,
                        style: AppTextStyles.bodyMuted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.iconChipBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  station.code,
                  style: AppTextStyles.label.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
