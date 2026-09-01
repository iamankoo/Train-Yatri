import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/features/search/journey_search_state.dart';

const _nda = Station(stationId: 1, code: 'NDA', name: 'New Delta Alpha');
const _mcb = Station(stationId: 2, code: 'MCB', name: 'Mumbai Central Beta');

void main() {
  test('starts with no stations selected and today as the date', () {
    final controller = JourneySearchController();
    final today = DateTime.now();

    expect(controller.state.from, isNull);
    expect(controller.state.to, isNull);
    expect(controller.state.date.year, today.year);
    expect(controller.state.date.month, today.month);
    expect(controller.state.date.day, today.day);
    expect(controller.state.isValid, isFalse);
  });

  test('setFrom/setTo make the state valid once both differ', () {
    final controller = JourneySearchController()
      ..setFrom(_nda)
      ..setTo(_mcb);

    expect(controller.state.isValid, isTrue);
    expect(controller.state.hasSameStationSelected, isFalse);
  });

  test('selecting the same station for both From and To is invalid', () {
    final controller = JourneySearchController()
      ..setFrom(_nda)
      ..setTo(_nda);

    expect(controller.state.isValid, isFalse);
    expect(controller.state.hasSameStationSelected, isTrue);
  });

  test('swap exchanges From and To and preserves the date', () {
    final date = DateTime(2026, 12, 25);
    final controller = JourneySearchController()
      ..setFrom(_nda)
      ..setTo(_mcb)
      ..setDate(date)
      ..swap();

    expect(controller.state.from, _mcb);
    expect(controller.state.to, _nda);
    expect(controller.state.date, date);
  });

  test('swap works even with only one station selected', () {
    final controller = JourneySearchController()
      ..setFrom(_nda)
      ..swap();

    expect(controller.state.from, isNull);
    expect(controller.state.to, _nda);
  });

  test('clearFrom/clearTo only clear their own field', () {
    final controller = JourneySearchController()
      ..setFrom(_nda)
      ..setTo(_mcb)
      ..clearFrom();

    expect(controller.state.from, isNull);
    expect(controller.state.to, _mcb);

    controller.clearTo();
    expect(controller.state.to, isNull);
  });

  test('setDate updates only the date', () {
    final controller = JourneySearchController()..setFrom(_nda);
    final date = DateTime(2026, 3, 15);
    controller.setDate(date);

    expect(controller.state.date, date);
    expect(controller.state.from, _nda);
  });

  test('restore sets From, To and date together in one step', () {
    final controller = JourneySearchController();
    final date = DateTime(2026, 5, 1);
    controller.restore(from: _nda, to: _mcb, date: date);

    expect(controller.state.from, _nda);
    expect(controller.state.to, _mcb);
    expect(controller.state.date, date);
    expect(controller.state.isValid, isTrue);
  });
}
