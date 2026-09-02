import 'package:flutter/material.dart';

import '../../../domain/entities/live_train_status.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/date_formatter.dart';
import 'live_delay_indicator.dart';

/// A real, scheduled stoppage's state relative to the train's live
/// position - derived only from real `sequence`/`isHalt` numbers,
/// never a timer or a guess. `neutral` is used only when the live
/// position itself is unknown, so a stoppage is never shown as
/// (incorrectly) passed or upcoming without real position data behind
/// it.
enum _StoppageColor { passed, next, future, neutral }

sealed class _TimelineEntry {
  const _TimelineEntry();
}

/// A route point that is *not* a real stoppage (`isHalt != true`) -
/// rendered with the plain, pre-existing station presentation, never
/// the colored stoppage fence.
final class _PassThroughEntry extends _TimelineEntry {
  const _PassThroughEntry(this.stop, this.isPast);
  final LiveRouteStop stop;
  final bool isPast;
}

/// A real stoppage (`isHalt == true`). [isCurrentPosition] is true
/// only when this exact stop is where `currentLocation` says the train
/// is right now (`isHalt == true` there too) - the one row that also
/// carries the live delay indicator.
final class _StoppageEntry extends _TimelineEntry {
  const _StoppageEntry(this.stop, this.color, this.isCurrentPosition);
  final LiveRouteStop stop;
  final _StoppageColor color;
  final bool isCurrentPosition;
}

/// The train is between two stops right now (`currentLocation.isHalt
/// == false`) - inserted in place of a single stop. Never invents a
/// station: [previousLabel]/[nextLabel] come straight from
/// [LiveTrainStatus.previousHalt]/[nextHalt].
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

class _StopClassification {
  const _StopClassification({
    required this.isRealStoppage,
    required this.color,
    required this.isPast,
    required this.isCurrentPosition,
  });

  final bool isRealStoppage;
  final _StoppageColor? color;
  final bool isPast;
  final bool isCurrentPosition;
}

/// The live route: every real railway station the route passes through
/// is still shown, but only genuine, scheduled stoppages get the
/// colored "TRAIN STOPPAGE" fence - never a pass-through point. The
/// page auto-scrolls to the train's real current position once, on
/// first load (never on a background poll refresh, which would yank
/// the view while someone is reading), and the same real
/// `delayMinutes` shown in [LiveStatusHeaderCard] travels with that
/// live-position marker.
class LiveRouteTimeline extends StatefulWidget {
  const LiveRouteTimeline({
    required this.route,
    required this.currentLocation,
    required this.delayMinutes,
    this.previousHalt,
    this.nextHalt,
    super.key,
  });

  final List<LiveRouteStop> route;
  final LiveCurrentLocation? currentLocation;

  /// The exact same value `LiveStatusHeaderCard` shows - never a
  /// second, independently-derived delay.
  final int? delayMinutes;

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

  /// One classification per [route] entry, in order. See the module
  /// doc comment on [_StoppageColor] for what "passed"/"next"/"future"
  /// mean and how they're derived.
  List<_StopClassification> _classify() {
    final currentSequence = widget.currentLocation?.sequence;
    final currentIsHalt = widget.currentLocation?.isHalt;

    if (currentSequence == null) {
      return [
        for (final stop in widget.route)
          _StopClassification(
            isRealStoppage: stop.isHalt == true,
            color: stop.isHalt == true ? _StoppageColor.neutral : null,
            isPast: false,
            isCurrentPosition: false,
          ),
      ];
    }

    // When the train is at a halt, that halt itself is the reference
    // point ("passed" is strictly before it). When it's between
    // stations (or halt status is unknown), currentSequence names the
    // stop already departed, so "passed" includes that stop itself.
    final passedThreshold = currentIsHalt == false
        ? currentSequence
        : currentSequence - 1;

    var nextAssigned = false;
    final result = <_StopClassification>[];

    for (final stop in widget.route) {
      final sequence = stop.sequence;
      final isRealStoppage = stop.isHalt == true;

      if (sequence == null) {
        result.add(
          _StopClassification(
            isRealStoppage: isRealStoppage,
            color: isRealStoppage ? _StoppageColor.neutral : null,
            isPast: false,
            isCurrentPosition: false,
          ),
        );
        continue;
      }

      final isPast = sequence <= passedThreshold;

      if (!isRealStoppage) {
        result.add(
          _StopClassification(
            isRealStoppage: false,
            color: null,
            isPast: isPast,
            isCurrentPosition: false,
          ),
        );
        continue;
      }

      if (isPast) {
        result.add(
          const _StopClassification(
            isRealStoppage: true,
            color: _StoppageColor.passed,
            isPast: true,
            isCurrentPosition: false,
          ),
        );
      } else if (!nextAssigned) {
        nextAssigned = true;
        result.add(
          _StopClassification(
            isRealStoppage: true,
            color: _StoppageColor.next,
            isPast: false,
            isCurrentPosition:
                currentIsHalt == true && sequence == currentSequence,
          ),
        );
      } else {
        result.add(
          const _StopClassification(
            isRealStoppage: true,
            color: _StoppageColor.future,
            isPast: false,
            isCurrentPosition: false,
          ),
        );
      }
    }
    return result;
  }

  List<_TimelineEntry> _buildEntries() {
    final classifications = _classify();
    final currentSequence = widget.currentLocation?.sequence;
    final isHalt = widget.currentLocation?.isHalt;
    final entries = <_TimelineEntry>[];
    var segmentInserted = false;

    for (var i = 0; i < widget.route.length; i++) {
      final stop = widget.route[i];
      final classification = classifications[i];

      if (classification.isRealStoppage) {
        entries.add(
          _StoppageEntry(
            stop,
            classification.color!,
            classification.isCurrentPosition,
          ),
        );
      } else {
        entries.add(_PassThroughEntry(stop, classification.isPast));
      }

      // Between stations: insert the live segment right after the
      // stop the train just departed (currentSequence itself), before
      // whatever comes next - mirrors the "passed" boundary above.
      if (isHalt == false &&
          !segmentInserted &&
          stop.sequence != null &&
          stop.sequence == currentSequence) {
        entries.add(
          _SegmentEntry(
            previousLabel:
                widget.previousHalt?.stationName ??
                widget.previousHalt?.stationCode ??
                stop.stationName ??
                stop.stationCode,
            nextLabel:
                widget.nextHalt?.stationName ?? widget.nextHalt?.stationCode,
            segmentProgress: widget.currentLocation?.segmentProgress,
            isActualPosition: widget.currentLocation?.isActualPosition,
          ),
        );
        segmentInserted = true;
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
            _PassThroughEntry(:final stop, :final isPast) => _PassThroughRow(
              stop: stop,
              isPast: isPast,
              isLast: i == entries.length - 1,
            ),
            _StoppageEntry(
              :final stop,
              :final color,
              :final isCurrentPosition,
            ) =>
              _StoppageRow(
                key: isCurrentPosition ? _focusKey : null,
                stop: stop,
                color: color,
                isCurrentPosition: isCurrentPosition,
                delayMinutes: widget.delayMinutes,
                isLast: i == entries.length - 1,
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
                delayMinutes: widget.delayMinutes,
              ),
          },
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.color, required this.isLast, this.filled = false});

  final Color color;
  final bool isLast;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Column(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: filled ? color : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: filled ? 0 : 1.5),
            ),
          ),
          if (!isLast)
            Expanded(child: Container(width: 1.5, color: AppColors.divider)),
        ],
      ),
    );
  }
}

/// The unchanged, pre-existing plain station row - used only for route
/// points that are not real stoppages.
class _PassThroughRow extends StatelessWidget {
  const _PassThroughRow({
    required this.stop,
    required this.isPast,
    required this.isLast,
  });

  final LiveRouteStop stop;
  final bool isPast;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final name = stop.stationName ?? stop.stationCode ?? 'Unknown station';
    final time =
        stop.actualArrival ??
        stop.scheduledArrival ??
        stop.actualDeparture ??
        stop.scheduledDeparture;

    return Semantics(
      label: name,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Rail(
              color: isPast ? AppColors.success : AppColors.divider,
              isLast: isLast,
              filled: !isPast,
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
                        style: AppTextStyles.body.copyWith(
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

/// A real, scheduled stoppage - the compact colored "fence" is the
/// visual focus here. The live delay indicator is shown only when
/// [isCurrentPosition] is true - the one stoppage that is also the
/// train's current live position; every other stoppage never shows
/// one (never a second, independent delay reading; never shown on a
/// stoppage that isn't the live position). [delayMinutes] itself may
/// still be `null` even when [isCurrentPosition] is true - that's the
/// real "delay unknown" case, distinct from "not the current
/// position" (which simply omits the indicator entirely).
class _StoppageRow extends StatelessWidget {
  const _StoppageRow({
    super.key,
    required this.stop,
    required this.color,
    required this.isCurrentPosition,
    required this.delayMinutes,
    required this.isLast,
  });

  final LiveRouteStop stop;
  final _StoppageColor color;
  final bool isCurrentPosition;
  final int? delayMinutes;
  final bool isLast;

  Color get _fenceColor => switch (color) {
    _StoppageColor.passed => AppColors.error,
    _StoppageColor.next => AppColors.success,
    _StoppageColor.future => AppColors.amber,
    _StoppageColor.neutral => AppColors.textSecondary,
  };

  String get _label => switch (color) {
    _StoppageColor.passed => 'TRAIN STOPPAGE — PASSED',
    _StoppageColor.next => 'TRAIN STOPPAGE — NEXT',
    _StoppageColor.future || _StoppageColor.neutral => 'TRAIN STOPPAGE',
  };

  /// Only the "next" stoppage pulses, and only while it's also the
  /// live position - a passed or future stoppage is always static.
  bool get _shouldPulse => color == _StoppageColor.next;

  @override
  Widget build(BuildContext context) {
    final name = stop.stationName ?? stop.stationCode ?? 'Unknown station';
    final time =
        stop.actualArrival ??
        stop.scheduledArrival ??
        stop.actualDeparture ??
        stop.scheduledDeparture;

    return Semantics(
      label: isCurrentPosition
          ? '$name. $_label. Current position.'
          : '$name. $_label.',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Rail(color: _fenceColor, isLast: isLast, filled: true),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PulsingFence(
                  color: _fenceColor,
                  pulse: _shouldPulse,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: AppTextStyles.title,
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
                        const SizedBox(height: 2),
                        Text(
                          _label,
                          style: AppTextStyles.label.copyWith(
                            color: _fenceColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (isCurrentPosition) ...[
                          const SizedBox(height: 4),
                          LiveDelayIndicator(delayMinutes: delayMinutes),
                        ],
                      ],
                    ),
                  ),
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
    this.delayMinutes,
  });

  final String? previousLabel;
  final String? nextLabel;
  final double? segmentProgress;
  final bool? isActualPosition;
  final int? delayMinutes;

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
      label: 'Live position: between $label. Current position.',
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
                  const _MiniPulsingDot(color: AppColors.primary),
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
              const SizedBox(height: 4),
              LiveDelayIndicator(delayMinutes: delayMinutes),
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

/// A compact rectangular "fence" with rounded corners around a
/// stoppage - a colored border, subtly pulsing only when [pulse] is
/// true and the platform's reduced-motion setting isn't on. Only the
/// border/background opacity pulses; the box never changes size, so
/// there is no layout movement.
class _PulsingFence extends StatefulWidget {
  const _PulsingFence({
    required this.color,
    required this.pulse,
    required this.child,
  });

  final Color color;
  final bool pulse;
  final Widget child;

  @override
  State<_PulsingFence> createState() => _PulsingFenceState();
}

class _PulsingFenceState extends State<_PulsingFence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.45,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingFence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !oldWidget.pulse) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && oldWidget.pulse) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.pulse && !reduceMotion;

    Widget fence(double opacity) => Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.color.withValues(alpha: opacity),
          width: 1.5,
        ),
        color: widget.color.withValues(alpha: 0.05 * opacity),
      ),
      child: widget.child,
    );

    if (!animate) return fence(1.0);

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => fence(_opacity.value),
    );
  }
}

class _MiniPulsingDot extends StatefulWidget {
  const _MiniPulsingDot({required this.color});
  final Color color;

  @override
  State<_MiniPulsingDot> createState() => _MiniPulsingDotState();
}

class _MiniPulsingDotState extends State<_MiniPulsingDot>
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
