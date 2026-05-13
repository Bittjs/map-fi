<h1 align="center">📍 MapFi</h1>
<p align="center">
  <em>Удобная офлайн-карта Wi-Fi точек твоего города прямо в кармане!</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?style=for-the-badge&logo=flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-teal?style=for-the-badge&logo=dart" />
  <img src="https://img.shields.io/badge/Architecture-MVVM-orange?style=for-the-badge" />
</p>

---
## Реализованные функции:

- 🗺 Настоящий офлайн-режим - Отображение карты и точек работает без интернета благодаря JSON-хранилищу и кэшированию тайлов (FMTC) в отличии от альтернатив))
- 🔍 Поиск и фильтрация - Мгновенный поиск по названию сети (SSID) или BSSID, а также гибкая сортировка (по алфавиту или популярности точек)
- 🔄 Синхронизация - Обновление локальной базы данных по прямой ссылке (например, с GitHub)
- 🛡 Верификация - Возможность подтвердить существование точки, если ты находишься в ближнем радиусе и подключен к этой Wi-Fi сети

### Как использовать?

1. Запустите приложение и нажмите «Загрузить базу точек» (или выберите свой .json файл с точками, подробнее про структуру)
2. Используй верхнюю панель для поиска нужной сети или просто жамкай по маркерам на карте
3. Потяни нижнюю шторку вверх, чтобы увидеть весь список доступных сетей
4. Приехал на место? Подключись к Wi-Fi, нажми стрелочку рядом с точкой в списке и выбери «Верифицировать»!

---

## Технические детали:

### Структура проекта


lib/
  models/            # Модели данных (WiFiPoint)
  viewmodels/        # Управление состоянием (MapViewModel)
  services/          # Сервисы работы с сетью
  views/
    screens/
    widgets/
app_theme.dart     # Стили и цветовая схема приложения
main.dart

### Установка и сборка для локального запуска
git clone [https://github.com/bittjs/MapFi.git](https://github.com/bittjs/map-fi.git)
cd map-fi

flutter pub get

flutter run

<p align="center">
    <b>Bittjs - <a href="https://t.me/shitcodenotes">shitcodenotes</a></b>
    <b>SamDe7 - <a href="https://github.com/SamDe7">github</a></b>
</p>
