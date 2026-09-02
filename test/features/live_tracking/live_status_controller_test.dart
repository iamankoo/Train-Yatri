import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/repositories/live_status_repository.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/domain/services/live_status_presentation.dart';
import 'package:train_yatri/features/live_tracking/live_status_controller.dart';

LiveTrainStatus _status({int? delayMinutes}) => LiveTrainStatus(
  trainNumber: '12951',
  trainName: 'Test Rajdhani',
  journeyDate: '2026-09-02',
  status: LiveStatusCategory.running,
  delayMinutes: delayMinutes,
  lastUpdatedAt: null,
  isLive: true,
  currentLocation: null,
  previousHalt: null,
  nextHalt: null,
  route: const [],
  exceptions: const [],
);

class _ScriptedRepository implements LiveStatusRepository {
  _ScriptedRepository(this.responses);

  final List<Object> responses; // LiveTrainStatus or LiveStatusException
  int callCount = 0;

  @override
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  }) async {
    final response = responses[callCount.clamp(0, responses.length - 1)];
    callCount++;
    if (response is LiveStatusException) throw response;
    return response as LiveTrainStatus;
  }
}

void main() {
  testWidgets('starts loading, then becomes available after the first fetch', (
    tester,
  ) async {
    final repository = _ScriptedRepository([_status()]);
    final controller = LiveStatusController(
      repository: repository,
      trainNumber: '12951',
    );

    expect(controller.state, isA<LiveStatusLoading>());
    await tester.pump();

    final state = controller.state;
    expect(state, isA<LiveStatusAvailable>());
    expect((state as LiveStatusAvailable).status.trainNumber, '12951');
    expect(state.isStale, isFalse);
    controller.dispose();
  });

  testWidgets(
    'a first-load failure becomes Unavailable with the safe message',
    (tester) async {
      final repository = _ScriptedRepository([
        const LiveStatusException(
          LiveStatusFailureCategory.notFound,
          "Live status isn't available for this train.",
        ),
      ]);
      final controller = LiveStatusController(
        repository: repository,
        trainNumber: '99999',
      );

      await tester.pump();

      final state = controller.state;
      expect(state, isA<LiveStatusUnavailable>());
      expect(
        (state as LiveStatusUnavailable).message,
        "Live status isn't available for this train.",
      );
      expect(state.category, LiveStatusFailureCategory.notFound);
      controller.dispose();
    },
  );

  testWidgets(
    'a poll failure after a successful load keeps showing the old data, marked stale',
    (tester) async {
      final repository = _ScriptedRepository([
        _status(),
        const LiveStatusException(
          LiveStatusFailureCategory.network,
          "Couldn't load live status.",
        ),
      ]);
      final controller = LiveStatusController(
        repository: repository,
        trainNumber: '12951',
        pollInterval: const Duration(seconds: 5),
      );

      await tester.pump();
      expect(controller.state, isA<LiveStatusAvailable>());
      expect((controller.state as LiveStatusAvailable).isStale, isFalse);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      final state = controller.state;
      expect(state, isA<LiveStatusAvailable>());
      expect((state as LiveStatusAvailable).isStale, isTrue);
      // The real, previously-fetched status is still shown - never
      // replaced by a fabricated or blank value.
      expect(state.status.trainNumber, '12951');
      controller.dispose();
    },
  );

  testWidgets('polls again roughly every pollInterval while alive', (
    tester,
  ) async {
    final repository = _ScriptedRepository([_status(), _status(), _status()]);
    final controller = LiveStatusController(
      repository: repository,
      trainNumber: '12951',
      pollInterval: const Duration(seconds: 10),
    );

    await tester.pump();
    expect(repository.callCount, 1);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(repository.callCount, 2);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(repository.callCount, 3);
    controller.dispose();
  });

  testWidgets(
    'refreshNow triggers an immediate fetch outside the poll schedule',
    (tester) async {
      final repository = _ScriptedRepository([_status(), _status()]);
      final controller = LiveStatusController(
        repository: repository,
        trainNumber: '12951',
        pollInterval: const Duration(minutes: 5),
      );

      await tester.pump();
      expect(repository.callCount, 1);

      await controller.refreshNow();
      expect(repository.callCount, 2);
      controller.dispose();
    },
  );

  testWidgets(
    'never fabricates a delay value - null stays null through the state',
    (tester) async {
      final repository = _ScriptedRepository([_status(delayMinutes: null)]);
      final controller = LiveStatusController(
        repository: repository,
        trainNumber: '12951',
      );

      await tester.pump();

      final state = controller.state as LiveStatusAvailable;
      expect(state.status.delayMinutes, isNull);
      controller.dispose();
    },
  );
}
