import 'package:flutter/material.dart';

import '../../../domain/entities/live_train_status.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/date_formatter.dart';

enum _StopState { past, current, upcoming }

sealed class _TimelineEntry {
  const _TimelineEntry();
}

final class _StopEntry extends _TimelineEntry {
  const _StopEntry(this.stop, this.state);
  final LiveRouteStop stop;
  final _StopState state;
}

/// The train is between two stops right now - inserted in place of a
/// single "current" stop when `currentLocation.isHalt == false`. Never
/// invents a station: [previousLabel]/[nextLabel] come straight from
/// [LiveTrainStatus.previousHalt]/[nextHalt], which are `null` exactly
/// when RailRadar didn't provide one.
final class _SegmentEntry extends _TimelineEntry {
  const _SegmentEntry({
    this.previousLabel,
    this.nextLabel,
    this.segmentProgress,
    this.isActualPosition,
  });
  final String? previousLabel;
  final String? nextLabel;
  final double? segmentProgress;
  final bool? isActualPosition;
}

/// The live route, with the train's real current position immediately
/// visible - the page auto-scrolls to it once, on first load (never on
/// a background poll refresh, which would yank the view while someone
/// is reading). Past/current/upcoming is derived only from
/// [LiveCurrentLocation.sequence] against each stop's own real
/// sequence number - never guessed from time of day.
class LiveRouteTimeline extends StatefulWidget {
  const LiveRouteTimeline({
    required this.route,
    required this.currentLocation,
    this.previousHalt,
    this.nextHalt,
    super.key,
  });

  final List<LiveRouteStop> route;
  final LiveCurrentLocation? currentLocation;
  final LiveHalt? previousHalt;
  final LiveHalt? nextHalt;

  @override
  State<LiveRouteTimeline> createState() => _LiveRouteTimelineState();
}

class _LiveRouteTimelineState extends State<LiveRouteTimeline> {
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  void _scrollToFocus() {
    final targetContext = _focusKey.currentContext;
    if (targetContext == null || !mounted) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.22,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  List<_TimelineEntry> _buildEntries() {
    final currentSequence = widget.currentLocation?.sequence;
    if (currentSequence == null) {
      return [
        for (final stop in widget.route) _StopEntry(stop, _StopState.upcoming),
      ];
    }

    final isHalt = widget.currentLocation?.isHalt;
    final entries = <_TimelineEntry>[];
    var segmentInserted = false;

    for (final stop in widget.route) {
      final sequence = stop.sequence;
      if (sequence == null) {
        entries.add(_StopEntry(stop, _StopState.upcoming));
        continue;
      }

      if (isHalt == false) {
        // Between stations: everything up to and including the
        // departed stop is past; the segment marker goes right after
        // it; everything beyond is upcoming.
        if (sequence <= currentSequence) {
          entries.add(_StopEntry(stop, _StopState.past));
          if (sequence == currentSequence && !segmentInserted) {
            entries.add(
              _SegmentEntry(
                previousLabel:
                    widget.previousHalt?.stationName ??
                    widget.previousHalt?.stationCode ??
                    stop.stationName ??
                    stop.stationCode,
                nextLabel:
                    widget.nextHalt?.stationName ??
                    widget.nextHalt?.stationCode,
                segmentProgress: widget.currentLocation?.segmentProgress,
                isActualPosition: widget.currentLocation?.isActualPosition,
              ),
            );
            segmentInserted = true;
          }
        } else {
          entries.add(_StopEntry(stop, _StopState.upcoming));
        }
      } else {
        final state = sequence < currentSequence
            ? _StopState.past
            : sequence == currentSequence
            ? _StopState.current
            : _StopState.upcoming;
        entries.add(_StopEntry(stop, state));
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          switch (entries[i]) {
            _StopEntry(:final stop, :final state) => _StopRow(
              stop: stop,
              state: state,
              isLast: i == entries.length - 1,
              focusKey: state == _StopState.current ? _focusKey : null,
            ),
            _SegmentEntry(
              :final previousLabel,
              :final nextLabel,
              :final segmentProgress,
              :final isActualPosition,
            ) =>
              _SegmentRow(
                key: _focusKey,
                previousLabel: previousLabel,
                nextLabel: nextLabel,
                segmentProgress: segmentProgress,
                isActualPosition: isActualPosition,
              ),
          },
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.state,
    required this.isLast,
    this.focusKey,
  });

  final LiveRouteStop stop;
  final _StopState state;
  final bool isLast;
  final Key? focusKey;

  @override
  Widget build(BuildContext context) {
    final name = stop.stationName ?? stop.stationCode ?? 'Unknown station';
    final time =
        stop.actualArrival ??
        stop.scheduledArrival ??
        stop.actualDeparture ??
        stop.scheduledDeparture;
    final isCurrent = state == _StopState.current;
    final isPast = state == _StopState.past;

    final dotColor = switch (state) {
      _StopState.past => AppColors.success,
      _StopState.current => AppColors.primary,
      _StopState.upcoming => AppColors.divider,
    };

    return Semantics(
      key: focusKey,
      label: isCurrent ? '$name, current station' : name,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Column(
                children: [
                  Container(
                    width: isCurrent ? 12 : 9,
                    height: isCurrent ? 12 : 9,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: isPast ? AppColors.surface : dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: dotColor,
                        width: isPast ? 1.5 : 0,
                      ),
                    ),
                    child: isPast
                        ? const Icon(
                            Icons.check,
                            size: 7,
                            color: AppColors.success,
                          )
                        : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 1.5, color: AppColors.divider),
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
                            ? AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              )
                            : AppTextStyles.body.copyWith(
                                color: isPast
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
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

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    super.key,
    this.previousLabel,
    this.nextLabel,
    this.segmentProgress,
    this.isActualPosition,
  });

  final String? previousLabel;
  final String? nextLabel;
  final double? segmentProgress;
  final bool? isActualPosition;

  @override
  Widget build(BuildContext context) {
    final label = previousLabel != null && nextLabel != null
        ? '$previousLabel  →  $nextLabel'
        : nextLabel != null
        ? 'Approaching $nextLabel'
        : previousLabel != null
        ? 'Left $previousLabel'
        : 'Between stations';

    return Semantics(
      label: 'Live position: between $label',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md, left: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _PulsingDot(color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              if (segmentProgress != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: segmentProgress!.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
              if (isActualPosition == false) ...[
                const SizedBox(height: 4),
                Text('Estimated position', style: AppTextStyles.label),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? dot : FadeTransition(opacity: _opacity, child: dot);
  }
}
