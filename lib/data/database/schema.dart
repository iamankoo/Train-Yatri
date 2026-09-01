/// The railway database's table structure.
///
/// [schemaVersion] identifies *this structure* - bump it whenever a
/// migration-worthy change is made to the DDL below. It is intentionally
/// separate from the railway dataset's own version (see
/// `DatasetMetadata.datasetVersion`): the tables can stay on schema
/// version 1 across many different dataset imports/updates.
const int schemaVersion = 1;

/// Executed in order against a fresh database file to create the full
/// railway schema. Idempotent (`IF NOT EXISTS`) so it is also safe to
/// run against a database that already has the tables, as a no-op.
const List<String> schemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS schema_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL,
    dataset_source TEXT NOT NULL,
    dataset_version TEXT,
    imported_at TEXT NOT NULL,
    station_count INTEGER NOT NULL,
    train_count INTEGER NOT NULL,
    route_stop_count INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS stations (
    station_id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_code TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    city TEXT,
    state TEXT,
    latitude REAL,
    longitude REAL
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_stations_normalized_code ON stations(normalized_code)',
  'CREATE INDEX IF NOT EXISTS idx_stations_normalized_name ON stations(normalized_name)',
  '''
  CREATE TABLE IF NOT EXISTS trains (
    train_id INTEGER PRIMARY KEY AUTOINCREMENT,
    number TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_number TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    confidence TEXT NOT NULL DEFAULT 'unknown'
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_trains_normalized_number ON trains(normalized_number)',
  'CREATE INDEX IF NOT EXISTS idx_trains_normalized_name ON trains(normalized_name)',
  '''
  CREATE TABLE IF NOT EXISTS route_stops (
    route_stop_id INTEGER PRIMARY KEY AUTOINCREMENT,
    train_id INTEGER NOT NULL REFERENCES trains(train_id),
    station_id INTEGER NOT NULL REFERENCES stations(station_id),
    stop_sequence INTEGER NOT NULL,
    arrival_time TEXT,
    departure_time TEXT,
    day_offset INTEGER NOT NULL DEFAULT 0,
    distance_km REAL,
    UNIQUE(train_id, stop_sequence)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_route_stops_train_sequence ON route_stops(train_id, stop_sequence)',
  'CREATE INDEX IF NOT EXISTS idx_route_stops_station ON route_stops(station_id)',
  'CREATE INDEX IF NOT EXISTS idx_route_stops_train_station ON route_stops(train_id, station_id)',
  '''
  CREATE TABLE IF NOT EXISTS running_days (
    train_id INTEGER PRIMARY KEY REFERENCES trains(train_id),
    monday INTEGER NOT NULL DEFAULT 0,
    tuesday INTEGER NOT NULL DEFAULT 0,
    wednesday INTEGER NOT NULL DEFAULT 0,
    thursday INTEGER NOT NULL DEFAULT 0,
    friday INTEGER NOT NULL DEFAULT 0,
    saturday INTEGER NOT NULL DEFAULT 0,
    sunday INTEGER NOT NULL DEFAULT 0,
    confidence TEXT NOT NULL DEFAULT 'unknown'
  )
  ''',
];
