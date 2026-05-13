//lib/models/wifi_database.dart
//Будущая имплементация нескольких активных конфигов
import './wifi_point.dart';

//Поля:
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