// Canonical Indian state/union-territory names, and a strict
// canonicalizer used by the railway data build pipeline
// (scripts/transform_railway_data.dart, scripts/enrich_station_states.dart)
// so every `state` value written to stations.csv - regardless of which
// source it came from - is one of these exact 36 names.
//
// The list itself is not invented: it is India's current 28 states + 8
// union territories, and matches the union-territory/state count
// (`admUnitCount: "36"`) reported by the geoBoundaries India ADM1
// boundary dataset this project also uses for geometric state
// enrichment (see docs/RAILWAY_DATABASE.md).
const List<String> canonicalStateNames = [
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
];

/// A handful of alternate spellings/old names actually observed in this
/// project's own upstream sources (datameet, Wikipedia) or in the
/// geoBoundaries release, keyed by their lowercase, diacritic-stripped
/// form. `orissa` is Odisha's pre-2011 official name (renamed by Act of
/// Parliament); the rest are casing/punctuation variants of a name
/// already on the canonical list above - not a different place.
const Map<String, String> _stateAliases = {
  'orissa': 'Odisha',
  'delhi nct': 'Delhi',
  'nct of delhi': 'Delhi',
  'jammu & kashmir': 'Jammu and Kashmir',
};

/// Strips the two combining-macron Latin vowels geoBoundaries' India
/// state names use (`ā`, `ī` - e.g. "Gujarāt", "Bihār") down to plain
/// ASCII, trims stray wiki-table parsing artifacts (a leading `|` seen
/// once in this project's own Wikipedia-sourced data), collapses
/// whitespace, and matches case-insensitively against
/// [canonicalStateNames] plus [_stateAliases].
///
/// Returns the canonical name, or `null` if the value cannot be
/// confidently matched to one of India's 36 states/UTs - callers must
/// treat `null` as "reject this value", never store it as-is and never
/// guess a closest match.
String? canonicalizeStateName(String raw) {
  var s = raw.trim();
  s = s.replaceAll('ā', 'a').replaceAll('ī', 'i');
  s = s.replaceFirst(RegExp(r'^\|+\s*'), ''); // stray table-cell artifact
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return null;

  final lower = s.toLowerCase();
  final alias = _stateAliases[lower];
  if (alias != null) return alias;

  for (final canonical in canonicalStateNames) {
    if (canonical.toLowerCase() == lower) return canonical;
  }
  return null;
}
