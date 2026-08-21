// lib/models/point_stats.dart
// Агрегированные отзывы по точке (GET /api/v1/points/{id}/stats).

class PointStats {
  final String pointId;
  final int regionId;
  final int days;
  final Map<String, int> counts;

  const PointStats({
    required this.pointId,
    required this.regionId,
    required this.days,
    required this.counts,
  });

  factory PointStats.fromJson(Map<String, dynamic> json) => PointStats(
        pointId: json['point_id'] as String,
        regionId: (json['region_id'] as num).toInt(),
        days: (json['days'] as num).toInt(),
        counts: (json['counts'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );

  /// Количество успешных проверок (verify).
  int get checks => counts['verify'] ?? 0;

  /// Количество жалоб (все типы, кроме verify).
  int get complaints => counts.entries
      .where((e) => e.key != 'verify')
      .fold(0, (sum, e) => sum + e.value);

  /// Признак «точка, возможно, недоступна»: много жалоб о том,
  /// что точки нет или она фейковая.
  bool get likelyUnavailable =>
      (counts['point_not_found'] ?? 0) + (counts['spam_fake'] ?? 0) >= 2;

  static const empty = PointStats(pointId: '', regionId: 0, days: 0, counts: {});
}