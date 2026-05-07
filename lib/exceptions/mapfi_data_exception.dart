// lib/exceptions/mapfi_data_exception.dart

/// Кастомное исключение для ошибок парсинга / чтения данных MapFi.
/// UI перехватывает его и показывает AlertDialog или SnackBar.
class MapFiDataException implements Exception {
  final String message;
  const MapFiDataException(this.message);

  @override
  String toString() => 'MapFiDataException: $message';
}
