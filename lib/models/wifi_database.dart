//lib/models/wifi_database.dart
import './wifi_point.dart';
class WiFiDatabase {

  final String id;
  final String name;

  final List<WiFiPoint> points;

  bool enabled;

  WiFiDatabase({
    required this.id,
    required this.name,
    required this.points,
    this.enabled = true,
  });
}