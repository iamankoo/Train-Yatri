import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/recent_live_trains_providers.dart';
import '../../domain/entities/recent_live_train.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/loading_state.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/train_yatri_card.dart';
import 'live_status_screen.dart';

final _trainNumberPattern = RegExp(r'^\d{1,6}$');

/// The Live tab's entry point (Block 6) - search a real train number to
/// open [LiveStatusScreen], or reopen a recently-viewed one. This
/// screen itself never calls RailRadar or the backend; it only
/// validates the number's shape client-side before navigating.
class LiveTabScreen extends ConsumerStatefulWidget {
  const LiveTabScreen({super.key});

  @override
  ConsumerState<LiveTabScreen> createState() => _LiveTabScreenState();
}

class _LiveTabScreenState extends ConsumerState<LiveTabScreen> {
  final _controller = TextEditingController();
  String? _fieldError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openTrain(String trainNumber, {String? trainName}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LiveStatusScreen(trainNumber: trainNumber, trainName: trainName),
      ),
    );
  }

  void _search() {
    final number = _controller.text.trim();
    if (!_trainNumberPattern.hasMatch(number)) {
      setState(() => _fieldError = 'Enter a valid train number');
      return;
    }
    setState(() => _fieldError = null);
    _openTrain(number);
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentLiveTrainsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live Status', style: AppTextStyles.heading),
              const SizedBox(height: AppSpacing.md),
              TrainYatriCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: 'Train number',
                        child: TextField(
                          controller: _controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: (_) => _search(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter train number',
                            errorText: _fieldError,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _search,
                      icon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                      ),
                      tooltip: 'Search',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Recent'),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: recentAsync.when(
                  loading: () =>
                      const LoadingState(message: 'Loading recent trains...'),
                  error: (_, _) => const ErrorState(
                    message: 'Could not load recent trains.',
                  ),
                  data: (recent) {
                    if (recent.isEmpty) {
                      return const EmptyState(
                        icon: Icons.train_outlined,
                        message: 'No recently viewed trains yet',
                      );
                    }
                    return ListView.separated(
                      itemCount: recent.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => _RecentTrainTile(
                        train: recent[index],
                        onTap: _openTrain,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTrainTile extends StatelessWidget {
  const _RecentTrainTile({required this.train, required this.onTap});

  final RecentLiveTrain train;
  final void Function(String trainNumber, {String? trainName}) onTap;

  @override
  Widget build(BuildContext context) {
    final label = train.trainName == null
        ? 'Train #${train.trainNumber}'
        : train.trainName!;

    return Semantics(
      button: true,
      label: 'View live status for $label',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => onTap(train.trainNumber, trainName: train.trainName),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.train_rounded, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '#${train.trainNumber}',
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
          ),
        ),
      ),
    );
  }
}
