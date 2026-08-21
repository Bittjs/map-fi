// lib/models/outbox_entry.dart
// Запись в очереди оффлайн-отправки (push-очередь для точек и фидбеков).

import 'dart:convert';

class OutboxEntry {
  static const String kindPoint = 'point';
  static const String kindFeedback = 'feedback';

  /// id из таблицы pending_outbox (null до сохранения в БД).
  final int? id;

  /// Тип операции: kindPoint или kindFeedback.
  final String kind;

  /// Данные операции в формате тела API-запроса.
  final Map<String, dynamic> payload;

  final DateTime createdAt;

  const OutboxEntry({
    this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  String get payloadJson => jsonEncode(payload);

  OutboxEntry copyWith({int? id}) => OutboxEntry(
        id: id ?? this.id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
      );
}