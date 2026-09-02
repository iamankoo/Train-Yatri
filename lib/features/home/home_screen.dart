import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_info.dart';
import '../../data/providers/update_providers.dart';
import '../../shared/theme/app_spacing.dart';
import '../update/widgets/update_available_dialog.dart';
import '../update/widgets/update_download_dialog.dart';
import 'widgets/brand_header.dart';
import 'widgets/hero_banner.dart';
import 'widgets/home_bottom_nav_bar.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/journey_search_card.dart';
import 'widgets/quick_actions_section.dart';
import 'widgets/recent_searches_section.dart';

/// Home screen foundation - real, interactive Flutter widgets laid out
/// to match the supplied `assets/mainpage.png` reference: brand header,
/// From/To/Date search card, quick actions, recent searches, bottom nav.
///
/// Also where the Block 4 update check (C1) surfaces: `updateCheckProvider`
/// runs in the background (never blocking this screen's own build/first
/// frame) and, the first time it resolves with a real update this
/// session, shows the update-available dialog.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<UpdateInfo?>>(updateCheckProvider, (previous, next) {
      final info = next.valueOrNull;
      if (info == null) return;
      if (ref.read(updateDialogShownProvider)) return;
      ref.read(updateDialogShownProvider.notifier).state = true;
      _promptUpdate(context, info);
    });

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: const [
            HomeTopBar(),
            SizedBox(height: AppSpacing.md),
            BrandHeader(),
            SizedBox(height: AppSpacing.lg),
            HeroBanner(),
            SizedBox(height: AppSpacing.lg),
            JourneySearchCard(),
            SizedBox(height: AppSpacing.lg),
            QuickActionsSection(),
            SizedBox(height: AppSpacing.xl),
            RecentSearchesSection(),
          ],
        ),
      ),
      bottomNavigationBar: const HomeBottomNavBar(),
    );
  }

  Future<void> _promptUpdate(BuildContext context, UpdateInfo info) async {
    if (!context.mounted) return;
    final wantsUpdate = await showUpdateAvailableDialog(context, info);
    if (wantsUpdate == true && context.mounted) {
      await startUpdateDownloadFlow(context, info);
    }
  }
}
