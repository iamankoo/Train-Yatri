import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

/// `sqflite`'s default implementation talks to Android/iOS over a
/// platform channel that doesn't exist under `flutter test` (or in a
/// plain Dart script). This swaps in the FFI-backed factory so database
/// code can run for real - against a real (temporary) SQLite file -
/// instead of being skipped or mocked out.
void ensureSqfliteFfiInitialized() {
  if (_initialized) return;
  sqfliteFfiInit();
  _initialized = true;
}
