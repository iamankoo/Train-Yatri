/// A previously-run journey search, kept locally on-device so the user
/// can quickly repeat it. Stores station code/name (not the internal
/// `stationId`) so a restored search stays correct even if the
/// underlying database were ever rebuilt with different row ids -
/// restoring re-resolves the station by code.
final class RecentSearch {
  const RecentSearch({
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    required this.date,
    required this.searchedAt,
  });

  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;

  /// The journey date the user searched for.
  final DateTime date;

  /// When this search was performed - used only for ordering.
  final DateTime searchedAt;

  /// Two searches are "the same route" for de-duplication purposes if
  /// they share a from/to pair, regardless of date.
  String get routeKey => '$fromCode>$toCode';

  Map<String, Object?> toJson() => {
    'fromCode': fromCode,
    'fromName': fromName,
    'toCode': toCode,
    'toName': toName,
    'date': date.toIso8601String(),
    'searchedAt': searchedAt.toIso8601String(),
  };

  static RecentSearch? tryFromJson(Map<String, Object?> json) {
    final fromCode = json['fromCode'] as String?;
    final fromName = json['fromName'] as String?;
    final toCode = json['toCode'] as String?;
    final toName = json['toName'] as String?;
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final searchedAt = DateTime.tryParse(json['searchedAt'] as String? ?? '');
    if (fromCode == null ||
        fromName == null ||
        toCode == null ||
        toName == null ||
        date == null ||
        searchedAt == null) {
      return null;
    }
    return RecentSearch(
      fromCode: fromCode,
      fromName: fromName,
      toCode: toCode,
      toName: toName,
      date: date,
      searchedAt: searchedAt,
    );
  }
}
