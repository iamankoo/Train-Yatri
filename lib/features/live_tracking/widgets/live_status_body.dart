import 'package:flutter/material.dart';

import '../../../domain/services/live_status_presentation.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/loading_state.dart';
import 'live_exception_banner.dart';
import 'live_route_timeline.dart';
import 'live_status_header_card.dart';

/// The status/route rendering shared between the standalone
/// `LiveStatusScreen` (Live tab, recent trains) and Train Details'
/// inline live section - one real implementation, reused rather than
/// duplicated per-entry-point.
class LiveStatusBody extends StatelessWidget {
  const LiveStatusBody({
    required this.state,
    required this.onRetry,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.xl,
    ),
    super.key,
  });

  final LiveStatusState state;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry padding;

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
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isStale) const StaleLiveNotice(),
                for (final exception in status.exceptions) ...[
                  LiveExceptionBanner(exception: exception),
                  const SizedBox(height: AppSpacing.sm),
                ],
                LiveStatusHeaderCard(status: status),
                if (status.route.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  LiveRouteTimeline(
                    route: status.route,
                    currentLocation: status.currentLocation,
                    previousHalt: status.previousHalt,
                    nextHalt: status.nextHalt,
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

class StaleLiveNotice extends StatelessWidget {
  const StaleLiveNotice({super.key});

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
