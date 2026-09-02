import 'route_stop.dart';
import 'station.dart';

/// One stop of a train's route, paired with the [Station] it stops at -
/// what the Train Details screen (Block 4) actually needs to render a
/// route timeline without an extra per-stop lookup for every station on
/// a route that can have 50+ stops.
final class RouteStopWithStation {
  const RouteStopWithStation({required this.stop, required this.station});

  final RouteStop stop;
  final Station station;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteStopWithStation &&
          stop == other.stop &&
          station == other.station;

  @override
  int get hashCode => Object.hash(stop, station);

  @override
  String toString() => 'RouteStopWithStation(${station.code}, $stop)';
}
