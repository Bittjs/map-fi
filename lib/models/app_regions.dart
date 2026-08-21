// lib/models/app_regions.dart
// Справочник регионов (зеркалит таблицу regions в server/setup/001_init.sql).

class AppRegion {
  final int id;
  final String name;

  const AppRegion(this.id, this.name);

  factory AppRegion.fromJson(Map<String, dynamic> json) =>
      AppRegion((json['id'] as num).toInt(), json['name'] as String);
}

const List<AppRegion> kAppRegions = [
  AppRegion(54, 'Новосибирская область'),
  AppRegion(77, 'Москва'),
];